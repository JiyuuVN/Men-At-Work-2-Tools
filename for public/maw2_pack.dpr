program maw2_pack;

//--------------------------------------
//    ���������� ��� Men at Works! 2
//            �����: HeMet
//  Jiyuu-VN: http://http://jiyuu-vn.ru
//       �����: http://jiyuu.su
//--------------------------------------

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, Windows, Generics.Collections;

const
  MASK_ALL_FILES = '*.*';

var
  InFile : TFileStream;
  OutFile : TFileStream;
  SearchRec : TSearchRec;
  FileList : TStringList;
  FileSzList : TList<Cardinal>;
  i, lp_len : Cardinal; //������� � ����� ����� ����� � ������ � ������

//����������� ����� ������ �� ������
procedure GetDirFileList(Dir : string; var FileList : TStringList; var FileSzList : TList<Cardinal>);
var
  SR : TSearchRec;
begin
  if (Dir = '.') or (Dir = '..') then Exit;

  if FindFirst(Dir + '\' + MASK_ALL_FILES, faAnyFile, SR) <> 0 then Exit;

  if (SR.Attr and faDirectory) =  faDirectory then
    GetDirFileList(SR.Name, FileList, FileSzList);

  while FindNext(SR) = 0 do begin
    if (SR.Attr and faDirectory) =  faDirectory then begin
      if SR.Name <> '..' then
        GetDirFileList(Dir + '\' + SR.Name, FileList, FileSzList);
      Continue;
    end;
    FileList.Add(Dir + '\' + SR.Name);
    FileSzList.Add(SR.Size);
    lp_len := lp_len + Length(Dir + '\' + SR.Name);
  end;

  SysUtils.FindClose(SR);
end;


//���������� ������� ������
procedure AddArcTable(Arc : TStream; FileList : TStrings; FileSzList : TList<Cardinal>);
var
  buf, i, base_path_l, local_path_l, offset : Cardinal;
  Local_Path : AnsiString;
  b_buf : Byte;
begin
  //�������� ������� ����� � ������ (������ 4 ����� ������)
  //16 ���� �������� ������ ��� ������� ����� + ����� ����� ����� � ������
  // - ����� ����� ����� ���� � ������ ����������� �� ���-�� ������
  //+ 4 ����� (�� ����� ������)
  offset := 16 * FileList.Count + lp_len - Length(ParamStr(1)) * FileList.Count + 4;

  //������ �� ������� ���������� ��� ������ �������
  buf := offset - 4;
  Arc.Write(buf, SizeOf(buf));
  b_buf := 0;

  base_path_l := Length(ParamStr(1) + '\');
  for i := 0 to FileList.Count - 1 do begin

    //�������� ���� � ����� ������ ������
    Local_Path := Copy(FileList[i], base_path_l + 1, Length(FileList[i]) - base_path_l);

    local_path_l := Length(Local_Path);
    buf := 17 + local_path_l;
    Arc.Write(buf, SizeOf(buf));

    buf := 0;
    Arc.Write(buf, SizeOf(buf));

    Arc.Write(offset, SizeOf(offset));
    offset := offset + FileSzList[i];

    buf := FileSzList[i];
    Arc.Write(buf, SizeOf(buf));

    Arc.Write(Local_Path[1], local_path_l);
    Arc.Write(b_buf, SizeOf(b_buf));
  end;

end;

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
    //������������� ������� �������� ��� �������� � �������
    SetConsoleOutputCP(1251);

    WriteLn('����������� ��� Men at Works! 2 v0.2');
    WriteLn('Jiyuu-VN: http://jiyuu-vn.ru');
    WriteLn('�����: HeMet');

    //��������� ���-�� ����������
    if ParamCount <> 2 then begin
      Writeln('maw2_pack.exe dir output.dat');
      Exit;
    end;

    //������� ������ ������
    FileList := TStringList.Create;
    //� ������ �� ��������
    FileSzList := TList<Cardinal>.Create;
    //���� �����
    try
      Writeln('���� �����...');
      GetDirFileList(ParamStr(1), FileList, FileSzList);
      Writeln('����� ��������. ������ �������: ', FileList.Count);
    except
      on E : Exception do begin
        Writeln('����� �� ������: ' + E.Message);
        FreeAndNil(FileList);
        FreeAndNil(FileSzList);
        Exit;
      end;
    end;

    //������� �������� ����� ��� �������� ������
    OutFile := TFileStream.Create(ParamStr(2), fmCreate);

    //��������� � ���� �������
    try
      Writeln('������� ������� ������...');
      AddArcTable(OutFile, FileList, FileSzList);
    except
      on E : Exception do begin
        Writeln('�������� ������� �� �������: ' + E.Message );
        FreeAndNil(FileList);
        FreeAndNil(FileSzList);
        FreeAndNil(OutFile);
        Exit;
      end;
    end;

    //��������� � ���� �����
    try
      for i := 0 to FileList.Count - 1 do begin
        Writeln('��������� ����: ' + FileList[i]);
        InFile := TFileStream.Create(FileList[i], fmOpenRead);
        OutFile.CopyFrom(InFile, 0);
        FreeAndNil(InFile);
      end;
    finally
      FreeAndNil(InFile);
      FreeAndNil(OutFile);
    end;

    FreeAndNil(FileList);
    FreeAndNil(FileSzList);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
