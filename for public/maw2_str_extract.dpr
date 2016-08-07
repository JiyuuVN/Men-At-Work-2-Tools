program maw2_str_extract;

//--------------------------------------
//    Запаковщик для Men at Works! 2
//            Автор: HeMet
//    Jiyuu-VN: http://jiyuu-vn.ru
//       Форум: http://jiyuu.su
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
  InFile : TFileStream;             //файл со скриптом
  Status : Integer;                 //статус парсера
  LatinAlphabet : set of 'A'..'z';  // см. maw2_str_insert
  Digits : set of '0'..'9';
  AnotherChars : set of Char;
  str_buf : string;
  crd_buf : Cardinal;
  LabelList : TStringList;          //список меток: нас инетресуют их имена
                                    //поэтому это список строк

  Param_InFile_Num : byte;          //кол-во параметров
  No_Origin : Boolean;              //будем добавлять поле <Origin></Origin> или нет

//ищем текст
procedure SearchText (Script : TStream);
var
  Stream : TDIRegExSearchStream_Binary; //поток для бинарного поиска
  MP : RawByteString;                   //строка в виде сырого набора байт (можно конвертировать в любую кодировку)
  BasePos, ByteStart, ByteLength, CharStart, CharLength, i: Int64; //переменные для результатов поиска и счетчик
  idx : integer;                                                   //индекс
  str_buf : string;                                                //строковый буфер
  TranslateBase : TNativeXml;                                      //база для перевода
  Lines, Line : TXmlNode;                                          //струтуры для дерева базы
begin
  //начальная позиция (сразу за таблицей)
  //дело в том, что DIRegEx возращает смещение от адреса начала поиска, а не от начала файла
  BasePos := Script.Position;

  //создаем поток для поиска
  Stream := TDIRegExSearchStream_Binary.Create(nil);
  //размер кусков для анализа (взято из демки от разрабов)
  Stream.WorkSpaceSize := 512;

  //ругулярка которая описывает, что же есть наши строки в скрипте
  //т.е. строка - это некая последовательность начинающаяся с нулевого символа (разделитель от предыдушего опкода
  //далее возможно идут открывающие кавычки из Shift-JIS
  //после чего несколько раз может повторяться кусок из символов с нулевым символом на конце
  //причем перед нулем могуть быть закрывающие кавычки из Shift-JIS
  //после чего идет какой-нибудь символ недопустимый для строки (обычно номер следующего опкода)
  MP := '\x00(\x81\x69)?([-A-Za-z''_"., :;!?&'']{2,132}(\x81\x6A)?\x00)+[^-A-Za-z''_"., :;!?&''\x00]';

  //компилируем шаблок
  Stream.CompileMatchPatternStr(MP);

  //пошли искать
  Stream.SearchInit(Script);

  //создаем базу
  TranslateBase := TNativeXml.Create;
  //добавляем ветку строк
  TranslateBase.Root.Name := 'Lines';
  //получаем на неё указатель - туда и будем добавлять все строки
  Lines := TranslateBase.Root;

  i := 0;

  //пока что-то ещё ищется добавляем найденное
  while Stream.SearchNext(ByteStart, ByteLength, CharStart, CharLength) <> 0 do begin
    //если есть ещё найденные подстроки
    if Stream.SubStrCount > 0 then begin
      //копируем в буфер полезную инфу (без нулей и прочего)
      str_buf := Copy(Stream.MatchedStr, 2, ByteLength - 3);
      //делаем замену для нулевого символа и кавычек
      str_buf := TStringBuilder.Create(str_buf).Replace(#0, '\0').Replace(#$81#$69, '«').Replace(#$81#$6A, '»').ToString;

      //и если это вдруг метка а не текст под перевод, то пропускаем
      if LabelList.Find(str_buf, idx) then Continue;

      //добавляем ветку для новой строки
      Line := Lines.NodeNew('Line');

      //добавляем параметры адреса и длины
      Line.WriteAttributeInteger('StartPos', ByteStart + 1 + BasePos, -1);
      Line.WriteAttributeInteger('Length', ByteLength - 3, 0);
      //добавляем параметр пропускать её при сборке новго скрипта или нет
      Line.WriteAttributeBool('Skip', False);

      //в зависимости от ключа добавляем или нет оригинальный текст
      if not No_Origin then Line.NodeNew('Origin').ValueAsString := str_buf;
      //добавляем текст под перевод
      Line.NodeNew('Translated').ValueAsString := str_buf;

      //выводим в консолько что нашли (ИБД, ну, и что бы скушно не было :)
      Writeln(str_buf);
      Inc(i);
    end else Break;
  end;

  //добавляем к ветке строк параметр с их числом
  Lines.AttributeAdd('Count', i);

  //формат сохранения - читаемый, иначе всё в одну строку будет
  TranslateBase.XmlFormat := xfReadable;
  //сохраняем базу в файл
  TranslateBase.SaveToFile(ChangeFileExt(ParamStr(Param_InFile_Num), '.xml'));
  //освобождаем базу
  FreeAndNil(TranslateBase);
end;

// см. maw2_str_insert
function IsThisScript(Script : TStream) : Boolean;
var
  buf : Cardinal;
begin
  Script.Read(buf, SizeOf(buf));
  Result := buf = SCR_HEADER;
end;

// см. maw2_str_insert
function AvaibleForName(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c in AnotherChars);
end;

// см. maw2_str_insert
function AvaibleForLabel(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c = '_');
end;

// см. maw2_str_insert
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

// см. maw2_str_insert
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
    //если параметров не один и не два, значит что-то тут не так
    if (ParamCount < 1) or (ParamCount > 2) then Exit;

    //вариант для одного параметра
    if ParamCount = 1 then begin
      Param_InFile_Num := 1;
      No_Origin := False;
    end;
    //и для двух
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
      //открываем файл скрипта для чтения
      InFile := TFileStream.Create(ParamStr(Param_InFile_Num), fmOpenRead);

      //скрипт ли это?
      if not IsThisScript(InFile) then begin
       Writeln('This is not a script.');
       Exit;
      end;

      //создаем список для меток
      LabelList := TStringList.Create;

      // см. maw2_str_insert
      while Status = STATUS_PARSE_LABELS do begin
      ParseLabelName(InFile, str_buf);
      if Status = STATUS_PARSE_LABELS then begin
        LabelList.Add(str_buf);
        ParseLabelAdress(InFile, crd_buf);
      end;
    end;

    //сортируем метки
    LabelList.Sort;

    //ищем текст
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
