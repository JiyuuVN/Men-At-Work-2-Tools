program maw2_str_extract;

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
  Generics.Collections,
  NativeXml in '..\NativeXml308\NativeXml.pas',
  DIRegEx, DIRegEx_SearchStream;

{$SetPEFlags IMAGE_FILE_RELOCS_STRIPPED or IMAGE_FILE_DEBUG_STRIPPED}

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

const
  SCR_HEADER = $31465342; // 'BSF1'
  NULL_OP = 0;
  STATUS_PARSE_LABELS = 0;
  STATUS_PARSE_SCRIPT = 2;

var
  InFile : TFileStream;             //���� �� ��������
  Status : Integer;                 //������ �������
  LatinAlphabet : set of 'A'..'z';  // ��. maw2_str_insert
  Digits : set of '0'..'9';
  AnotherChars : set of Char;
  str_buf : string;
  crd_buf : Cardinal;
  LabelList : TStringList;          //������ �����: ��� ���������� �� �����
                                    //������� ��� ������ �����

  Param_InFile_Num : byte;          //���-�� ����������
  No_Origin : Boolean;              //����� ��������� ���� <Origin></Origin> ��� ���

//���� �����
procedure SearchText (Script : TStream);
var
  Stream : TDIRegExSearchStream_Binary; //����� ��� ��������� ������
  MP : RawByteString;                   //������ � ���� ������ ������ ���� (����� �������������� � ����� ���������)
  BasePos, ByteStart, ByteLength, CharStart, CharLength, i: Int64; //���������� ��� ����������� ������ � �������
  idx : integer;                                                   //������
  str_buf : string;                                                //��������� �����
  TranslateBase : TNativeXml;                                      //���� ��� ��������
  Lines, Line : TXmlNode;                                          //�������� ��� ������ ����
begin
  //��������� ������� (����� �� ��������)
  //���� � ���, ��� DIRegEx ��������� �������� �� ������ ������ ������, � �� �� ������ �����
  BasePos := Script.Position;

  //������� ����� ��� ������
  Stream := TDIRegExSearchStream_Binary.Create(nil);
  //������ ������ ��� ������� (����� �� ����� �� ��������)
  Stream.WorkSpaceSize := 512;

  //��������� ������� ���������, ��� �� ���� ���� ������ � �������
  //�.�. ������ - ��� ����� ������������������ ������������ � �������� ������� (����������� �� ����������� ������
  //����� �������� ���� ����������� ������� �� Shift-JIS
  //����� ���� ��������� ��� ����� ����������� ����� �� �������� � ������� �������� �� �����
  //������ ����� ����� ������ ���� ����������� ������� �� Shift-JIS
  //����� ���� ���� �����-������ ������ ������������ ��� ������ (������ ����� ���������� ������)
  MP := '\x00(\x81\x69)?([-A-Za-z''_"., :;!?&'']{2,132}(\x81\x6A)?\x00)+[^-A-Za-z''_"., :;!?&''\x00]';

  //����������� ������
  Stream.CompileMatchPatternStr(MP);

  //����� ������
  Stream.SearchInit(Script);

  //������� ����
  TranslateBase := TNativeXml.Create;
  //��������� ����� �����
  TranslateBase.Root.Name := 'Lines';
  //�������� �� �� ��������� - ���� � ����� ��������� ��� ������
  Lines := TranslateBase.Root;

  i := 0;

  //���� ���-�� ��� ������ ��������� ���������
  while Stream.SearchNext(ByteStart, ByteLength, CharStart, CharLength) <> 0 do begin
    //���� ���� ��� ��������� ���������
    if Stream.SubStrCount > 0 then begin
      //�������� � ����� �������� ���� (��� ����� � �������)
      str_buf := Copy(Stream.MatchedStr, 2, ByteLength - 3);
      //������ ������ ��� �������� ������� � �������
      str_buf := TStringBuilder.Create(str_buf).Replace(#0, '\0').Replace(#$81#$69, '�').Replace(#$81#$6A, '�').ToString;

      //� ���� ��� ����� ����� � �� ����� ��� �������, �� ����������
      if LabelList.Find(str_buf, idx) then Continue;

      //��������� ����� ��� ����� ������
      Line := Lines.NodeNew('Line');

      //��������� ��������� ������ � �����
      Line.WriteAttributeInteger('StartPos', ByteStart + 1 + BasePos, -1);
      Line.WriteAttributeInteger('Length', ByteLength - 3, 0);
      //��������� �������� ���������� � ��� ������ ����� ������� ��� ���
      Line.WriteAttributeBool('Skip', False);

      //� ����������� �� ����� ��������� ��� ��� ������������ �����
      if not No_Origin then Line.NodeNew('Origin').ValueAsString := str_buf;
      //��������� ����� ��� �������
      Line.NodeNew('Translated').ValueAsString := str_buf;

      //������� � ��������� ��� ����� (���, ��, � ��� �� ������ �� ���� :)
      Writeln(str_buf);
      Inc(i);
    end else Break;
  end;

  //��������� � ����� ����� �������� � �� ������
  Lines.AttributeAdd('Count', i);

  //������ ���������� - ��������, ����� �� � ���� ������ �����
  TranslateBase.XmlFormat := xfReadable;
  //��������� ���� � ����
  TranslateBase.SaveToFile(ChangeFileExt(ParamStr(Param_InFile_Num), '.xml'));
  //����������� ����
  FreeAndNil(TranslateBase);
end;

// ��. maw2_str_insert
function IsThisScript(Script : TStream) : Boolean;
var
  buf : Cardinal;
begin
  Script.Read(buf, SizeOf(buf));
  Result := buf = SCR_HEADER;
end;

// ��. maw2_str_insert
function AvaibleForName(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c in AnotherChars);
end;

// ��. maw2_str_insert
function AvaibleForLabel(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c = '_');
end;

// ��. maw2_str_insert
procedure ParseLabelName(Script : TStream; var LabelName : string);
var
  buf : Byte;
  name : string;
  StartPos : Int64;
begin
  buf := 255;
  name := '';
  StartPos := Script.Position;

  repeat
    Script.Read(buf, SizeOf(buf));
    if AvaibleForLabel(Char(buf)) then
      name := name + Char(buf) else
      if (buf <> NULL_OP) or ((buf = NULL_OP) and (name = '')) then begin
        name := '';
        buf := NULL_OP;
        Script.Position := StartPos;
        Status := STATUS_PARSE_SCRIPT;
      end;
  until buf = NULL_OP;

  LabelName := name;
end;

// ��. maw2_str_insert
procedure ParseLabelAdress(Script : TStream; var Adress : Cardinal);
var
  adr : Cardinal;
begin
  Script.Read(adr, SizeOf(adr));
  Adress := adr;
end;

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
    //���� ���������� �� ���� � �� ���, ������ ���-�� ��� �� ���
    if (ParamCount < 1) or (ParamCount > 2) then Exit;

    //������� ��� ������ ���������
    if ParamCount = 1 then begin
      Param_InFile_Num := 1;
      No_Origin := False;
    end;
    //� ��� ����
    if ParamCount = 2 then begin
      Param_InFile_Num := 2;
      No_Origin := ParamStr(1) = '-no';
    end;

    LatinAlphabet := ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
                      'P','Q','R','S','T','U','V','W','X','Y','X','a','b','c','d',
                      'e','f','g','h','i','j','k','l','m','n','o','p','q','r','s',
                      't','u','v','w','x','y','z'];
    Digits := ['0','1','2','3','4','5','6','7','8','9'];
    AnotherChars := ['_', '"', '.', ',', ' ', ':', ';', '!', '?', '&', '-', #39];

    try
      //��������� ���� ������� ��� ������
      InFile := TFileStream.Create(ParamStr(Param_InFile_Num), fmOpenRead);

      //������ �� ���?
      if not IsThisScript(InFile) then begin
       Writeln('This is not a script.');
       Exit;
      end;

      //������� ������ ��� �����
      LabelList := TStringList.Create;

      // ��. maw2_str_insert
      while Status = STATUS_PARSE_LABELS do begin
      ParseLabelName(InFile, str_buf);
      if Status = STATUS_PARSE_LABELS then begin
        LabelList.Add(str_buf);
        ParseLabelAdress(InFile, crd_buf);
      end;
    end;

    //��������� �����
    LabelList.Sort;

    //���� �����
    SearchText(inFile);

    finally
      FreeAndNil(LabelList);
      FreeAndNil(InFile);
    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
