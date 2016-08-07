program maw2_str_insert;

//--------------------------------------
//    ���������� ��� Men at Works! 2
//            �����: HeMet
//    Jiyuu-VN: http://jiyuu-vn.ru
//       �����: http://jiyuu.su
//--------------------------------------

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Windows,
  Generics.Defaults,
  Generics.Collections,
  RTLConsts,
  NativeXml in '..\NativeXml308\NativeXml.pas';

{$SetPEFlags IMAGE_FILE_RELOCS_STRIPPED or IMAGE_FILE_DEBUG_STRIPPED}

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

const
  SCR_HEADER = $31465342; // 'BSF1'
  NULL_OP = 0;
  STATUS_PARSE_LABELS = 0;
  STATUS_PARSE_SCRIPT = 2;

type
  TLabel = record     //��������� ��� �����
    adr : Cardinal;   //����� �� ������� ��� ���������
    offs : Cardinal;  //�������� �� �������� ��������� � ��������
    add : Integer;    //�������� � ������
    name : string;    //��� �����
  end;

  TFix = record       //��������� ��� ��������
    adr : Cardinal;   //�����
    fix : Integer;    //��������
  end;

  //����� ��� �������������� ��������� ����� � ������
  TLabelComparer = class(TComparer<TLabel>)
  public
    function Compare(const Left, Right: TLabel): Integer; override;
  end;

  //������ �����
  TLabelList<T> = class(TList<T>)
  private
    //��������� ��������� �� �����
    function GetItemPointer(Index: Integer): Pointer;
  public
    //������ ����������
    property Pointers[Index: Integer]: Pointer read GetItemPointer;
  end;

var
  ScrFile : TFileStream;            //���� ������� ��� ������
  NewScrMem : TMemoryStream;        //����� � ��� ���� ����� �������� ����� ����
  XmlFile : TNativeXml;             //XML-����
  Status : Integer;                 //������ ������� �����
  LatinAlphabet : set of 'A'..'z';  //��������� ���������� ��������
  Digits : set of '0'..'9';         //��������� �����
  AnotherChars : set of Char;       //��������� ������ ��������
  str_buf : string;                 //��������� �����
  crd_buf : Cardinal;               //������������� �����
  LabelList : TLabelList<TLabel>;   //������ �����
  lbl : TLabel;                     //����� ��� ���������� � LabelList
  LabelComparer : TLabelComparer;   //����� ��� ��������� �����
  FixList : TList<TFix>;            //������ ��������

//���������� �������� � ������� �����
procedure CalculateLabelFix;
var
  i, j : Cardinal;
  sum_fix : Integer;

begin
  sum_fix := 0;
  j := 0;

  //���������� ��� ����� � ������
  for i := 0 to LabelList.Count - 1 do begin
    //����� ����� ��������� �� ������� ������� �� ��������, �.�. �����
    //����� ��� ����������, � ������ ��� ���������, ����� ����� ���� ����������
    //�������, ����� ������ �� ����
    if j < FixList.Count then begin

      //���� ����� �������� ������ ��� ������ ���� ��������� �����
      //�� ������ ����������� ��������
      if FixList[j].adr > LabelList[i].adr then begin
        TLabel(LabelList.Pointers[i]^).add := sum_fix;
        Continue;
      end;

      //����������, ���������� ������ � ����������� ��������
      while FixList[j].adr <= LabelList[i].adr do begin
        sum_fix := sum_fix + FixList[j].fix;
        Inc(j);
        if j >= FixList.Count then Break;
      end;

    end;

    //�������� �������� ��� ����� ����������� �� ���� �� ��������
    TLabel(LabelList.Pointers[i]^).add := sum_fix;
    
  end;
end;

//������ � ����� ������������ �������
procedure FixLabel(Script : TStream);
var
  i, buf : Cardinal;
begin
  Script.Seek(4, soFromBeginning);

  for i := 0 to LabelList.Count - 1 do begin
    Script.Position := LabelList[i].offs;
    buf := LabelList[i].adr + LabelList[i].add;
    Script.Write(buf, SizeOf(buf));
  end;
end;

//������ ����� � �������
procedure InsertText(Script : TStream; BD : TNativeXml; NewScrFile : TStream);
var
  str_count, i, origin_len, trans_len, str_adr, copy_start : Cardinal;
  trans : AnsiString;
  fix : TFix;
begin
  //������ ���-�� �����
  str_count := BD.Root.ReadAttributeInteger('Count');
  //������ �������� ����������
  copy_start := 0;

  for i := 0 to str_count - 1 do begin
    //���� ������ �������� ��� "����������", ����������
    if BD.Root.Nodes[i].ReadAttributeBool('Skip') then Continue;

    //������ ����� ��������� ������
    origin_len := BD.Root.Nodes[i].ReadAttributeInteger('Length', -1);
    //� ��� ��������
    str_adr := BD.Root.Nodes[i].ReadAttributeInteger('StartPos', 0);

    //��������� ���� ����� �����
    fix.adr := str_adr;
    Script.Position := copy_start;
    //�������� ������������ ������� ������������� ������� ����� ��������
    //��� ������� ������ � ������
    NewScrFile.CopyFrom(Script, str_adr - copy_start);

    //����� ������������ �����
    trans := BD.Root.Nodes[i].FindNode('Translated').ValueAsString;

    //������ ������ ������-������� �� �������
    trans := TStringBuilder.Create(trans).Replace('\0', #0).ToString;
    //������ ��� ����� � ������
    trans_len := Length(trans);

    //��������� ����� ������
    NewScrFile.Write(trans[1], Length(trans));

    //��������� ��������
    fix.fix := (trans_len - origin_len);
    //��������� ����
    FixList.Add(fix);
    //������������� ����� �� ������ ���� �� �������� �������
    copy_start := str_adr + origin_len;
  end;

  //�������� ���� ���������� ����-���
  Script.Position := copy_start;
  NewScrFile.CopyFrom(Script, Script.Size - Script.Position);
end;

//��� ������ ������? ��������� ���������
function IsThisScript(Script : TStream) : Boolean;
var
  buf : Cardinal;
begin
  Script.Read(buf, SizeOf(buf));
  Result := buf = SCR_HEADER;
end;

//����� ������ ����� ����������� � �����
function AvaibleForName(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c in AnotherChars);
end;

//����� ������ ����� ����������� � �����
function AvaibleForLabel(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c = '_');
end;

//������ �������� � ������� �����
procedure ParseLabelName(Script : TStream; var LabelName : string);
var
  buf : Byte;
  name : string;
  StartPos : Int64;
begin
  buf := 255;
  name := '';
  StartPos := Script.Position;

  //��������� �� ��� ��� ���� �� ��������� �� �������� �������
  repeat
    //������ ��������� ����
    Script.Read(buf, SizeOf(buf));
    //���� ����� ����� ���� � ����� ��������� ��� � �����
    if AvaibleForLabel(Char(buf)) then
      name := name + Char(buf) else
      //���� ���������� ������������ ������ ��� �� ��� ����� �� �������
      //�������� �� � ������ ������ �� ������ �������
      if (buf <> NULL_OP) or ((buf = NULL_OP) and (name = '')) then begin
        name := '';
        buf := NULL_OP;
        Script.Position := StartPos;
        Status := STATUS_PARSE_SCRIPT;
      end;
  until buf = NULL_OP;

  //���������� ��� ������� �����
  LabelName := name;
end;

//������ ������ � ������� �����
procedure ParseLabelAdress(Script : TStream; var Adress : Cardinal);
var
  adr : Cardinal;
begin
  //������ ������ 4 ����� ������
  Script.Read(adr, SizeOf(adr));
  Adress := adr;
end;

{ TLabelComparer }

//���������� ����� �� ������� ���� ��������� �����
function TLabelComparer.Compare(const Left, Right: TLabel): Integer;
begin
  Result := Left.adr - Right.adr;
end;

{ TLabelList<T> }


function TLabelList<T>.GetItemPointer(Index: Integer): Pointer;
begin
  //���� ��� ������ ����������� ����������
  if (Index < 0) or (Index >= Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);
  //����� ���������� ��������� �� �������
  Result := @FItems[Index];
end;

begin
  try
    //������������� ������� �������� ��� �������� � �������
    SetConsoleOutputCP(1251);
    { TODO -oUser -cConsole Main : Insert code here }
    //��������� ������������ �������� ����������
    if ParamCount <> 2 then begin
      Writeln('maw2_str_insert.exe input.scr output.scr' + #10#13 + '����� � .scr ������ ������ ������ .xml!');
      Exit;
    end;

    LatinAlphabet := ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
                      'P','Q','R','S','T','U','V','W','X','Y','X','a','b','c','d',
                      'e','f','g','h','i','j','k','l','m','n','o','p','q','r','s',
                      't','u','v','w','x','y','z'];
    Digits := ['0','1','2','3','4','5','6','7','8','9'];
    AnotherChars := ['_', '"', '.', ',', ' ', ':', ';', '!', '?', '&', '-', #39];

    try
      //��������� ������ ������ ��� ������
      ScrFile := TFileStream.Create(ParamStr(1), fmOpenRead);
      //������� ����� � ��� ��� ������ �������
      NewScrMem := TMemoryStream.Create;

      //������ ���� � ���������
      XmlFile := TNativeXml.Create;
      XmlFile.LoadFromFile(ChangeFileExt(ParamStr(1), '.xml'));

      //��������� ������ �� � ������ ����������
      if not IsThisScript(ScrFile) then begin
        Writeln('��� �� ������.');
        Exit;
      end;

      //������� ������ ��� ����� � �������� �������� ���������
      LabelComparer := TLabelComparer.Create;
      LabelList := TLabelList<TLabel>.Create(LabelComparer);

      //������ ������� �����
      while Status = STATUS_PARSE_LABELS do begin
        ParseLabelName(ScrFile, str_buf);
        crd_buf := ScrFile.Position;
        if Status = STATUS_PARSE_LABELS then begin
          lbl.offs := crd_buf;
          ParseLabelAdress(ScrFile, crd_buf);
          lbl.adr := crd_buf;
          lbl.name := str_buf;
          LabelList.Add(lbl);
        end;
      end;

      //��������� �����
      LabelList.Sort;
      //������� ������ ������
      FixList := TList<TFix>.Create;
      //��������� �����
      InsertText(ScrFile, XmlFile, NewScrMem);
      //����������� ���� ��������
      FreeAndNil(XmlFile);
      //��������� ��������
      CalculateLabelFix;
      //������ �����
      FixLabel(NewScrMem);
      //����������� ������ �����
      FreeAndNil(FixList);
      //��������� ����� ������ � ����
      NewScrMem.SaveToFile(ParamStr(2));

    finally
      FreeAndNil(NewScrMem);
      FreeAndNil(LabelList);
      FreeAndNil(ScrFile);
    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
