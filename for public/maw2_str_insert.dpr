program maw2_str_insert;

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
  TLabel = record     //структура для метки
    adr : Cardinal;   //адрес на который она указывает
    offs : Cardinal;  //смещение по которому находится её описание
    add : Integer;    //поправка к адресу
    name : string;    //имя метки
  end;

  TFix = record       //структура для поправки
    adr : Cardinal;   //адрес
    fix : Integer;    //поправка
  end;

  //класс для нестандартного сравнения меток в списке
  TLabelComparer = class(TComparer<TLabel>)
  public
    function Compare(const Left, Right: TLabel): Integer; override;
  end;

  //список меток
  TLabelList<T> = class(TList<T>)
  private
    //получение указателя на метку
    function GetItemPointer(Index: Integer): Pointer;
  public
    //массив указателей
    property Pointers[Index: Integer]: Pointer read GetItemPointer;
  end;

var
  ScrFile : TFileStream;            //файл скрипта для чтения
  NewScrMem : TMemoryStream;        //поток в ОЗУ куда будет писаться новый файл
  XmlFile : TNativeXml;             //XML-файл
  Status : Integer;                 //Статус парсера меток
  LatinAlphabet : set of 'A'..'z';  //множество латинского алфавита
  Digits : set of '0'..'9';         //множетсво чисел
  AnotherChars : set of Char;       //множество прочих символов
  str_buf : string;                 //строковый буфер
  crd_buf : Cardinal;               //целочисленный буфер
  LabelList : TLabelList<TLabel>;   //список меток
  lbl : TLabel;                     //метка для добавления в LabelList
  LabelComparer : TLabelComparer;   //класс для сравнения меток
  FixList : TList<TFix>;            //список поправок

//вычисление поправок к адресам меток
procedure CalculateLabelFix;
var
  i, j : Cardinal;
  sum_fix : Integer;

begin
  sum_fix := 0;
  j := 0;

  //перебираем все метки в списке
  for i := 0 to LabelList.Count - 1 do begin
    //метки могут указывать за границу области со строками, т.е. метки
    //могут ещё оставаться, а строки все перебрали, тогда может быть исключение
    //смотрим, чтобы такого не было
    if j < FixList.Count then begin

      //если адрес поправки больше чем адресс куда указывает метка
      //то вносим накопленную поправку
      if FixList[j].adr > LabelList[i].adr then begin
        TLabel(LabelList.Pointers[i]^).add := sum_fix;
        Continue;
      end;

      //перебираем, сравниваем строки и накапливаем поправку
      while FixList[j].adr <= LabelList[i].adr do begin
        sum_fix := sum_fix + FixList[j].fix;
        Inc(j);
        if j >= FixList.Count then Break;
      end;

    end;

    //внесения поправок для меток указывающих за блок со строками
    TLabel(LabelList.Pointers[i]^).add := sum_fix;
    
  end;
end;

//запись в поток исправленных адресов
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

//замена строк в скрипте
procedure InsertText(Script : TStream; BD : TNativeXml; NewScrFile : TStream);
var
  str_count, i, origin_len, trans_len, str_adr, copy_start : Cardinal;
  trans : AnsiString;
  fix : TFix;
begin
  //узнаем кол-во строк
  str_count := BD.Root.ReadAttributeInteger('Count');
  //откуда начинаем копировать
  copy_start := 0;

  for i := 0 to str_count - 1 do begin
    //если строка помечена как "пропустить", пропускаем
    if BD.Root.Nodes[i].ReadAttributeBool('Skip') then Continue;

    //узнаем длину исходного текста
    origin_len := BD.Root.Nodes[i].ReadAttributeInteger('Length', -1);
    //и его смещение
    str_adr := BD.Root.Nodes[i].ReadAttributeInteger('StartPos', 0);

    //заполняем поле адрес фикса
    fix.adr := str_adr;
    Script.Position := copy_start;
    //копируем неизмененные участки оригинального скрипта между строками
    //как правило опкоды и прочее
    NewScrFile.CopyFrom(Script, str_adr - copy_start);

    //берем переведенный текст
    trans := BD.Root.Nodes[i].FindNode('Translated').ValueAsString;

    //делаем замену эскейп-символа на нулевой
    trans := TStringBuilder.Create(trans).Replace('\0', #0).ToString;
    //узнаем его длину в байтах
    trans_len := Length(trans);

    //вписываем новую строку
    NewScrFile.Write(trans[1], Length(trans));

    //вычисляем поправку
    fix.fix := (trans_len - origin_len);
    //добавляем фикс
    FixList.Add(fix);
    //устанавливаем адрес на первый байт за исходной строкой
    copy_start := str_adr + origin_len;
  end;

  //копируем весь оставшийся байт-код
  Script.Position := copy_start;
  NewScrFile.CopyFrom(Script, Script.Size - Script.Position);
end;

//это вообще скрипт? проверяем заголовок
function IsThisScript(Script : TStream) : Boolean;
var
  buf : Cardinal;
begin
  Script.Read(buf, SizeOf(buf));
  Result := buf = SCR_HEADER;
end;

//такой символ может содержаться в имени
function AvaibleForName(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c in AnotherChars);
end;

//такой символ может содержаться в метке
function AvaibleForLabel(c : Char) : Boolean;
begin
  Result := (c in LatinAlphabet) or (c in Digits) or (c = '_');
end;

//парсим названия в таблице меток
procedure ParseLabelName(Script : TStream; var LabelName : string);
var
  buf : Byte;
  name : string;
  StartPos : Int64;
begin
  buf := 255;
  name := '';
  StartPos := Script.Position;

  //повторяем до тех пор пока не добрались до нулевого символа
  repeat
    //читаем очередной байт
    Script.Read(buf, SizeOf(buf));
    //если такой может быть в метке добавляем его к имени
    if AvaibleForLabel(Char(buf)) then
      name := name + Char(buf) else
      //если встретился недопустимый символ или мы уже вышли за таблицу
      //обнуляем всё и меняем статус на разбор скрипта
      if (buf <> NULL_OP) or ((buf = NULL_OP) and (name = '')) then begin
        name := '';
        buf := NULL_OP;
        Script.Position := StartPos;
        Status := STATUS_PARSE_SCRIPT;
      end;
  until buf = NULL_OP;

  //возвращаем имя текущей метки
  LabelName := name;
end;

//парсим адреса в таблице меток
procedure ParseLabelAdress(Script : TStream; var Adress : Cardinal);
var
  adr : Cardinal;
begin
  //просто читаем 4 байта адреса
  Script.Read(adr, SizeOf(adr));
  Adress := adr;
end;

{ TLabelComparer }

//сравнивать будем по адресам куда указывают метки
function TLabelComparer.Compare(const Left, Right: TLabel): Integer;
begin
  Result := Left.adr - Right.adr;
end;

{ TLabelList<T> }


function TLabelList<T>.GetItemPointer(Index: Integer): Pointer;
begin
  //если вне списка выбрасываем исключение
  if (Index < 0) or (Index >= Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);
  //иначе возврашаем указатель на элемент
  Result := @FItems[Index];
end;

begin
  try
    //устанавливаем кодовую страницу для символов в консоли
    SetConsoleOutputCP(1251);
    { TODO -oUser -cConsole Main : Insert code here }
    //проверяем правильность заданных параметров
    if ParamCount <> 2 then begin
      Writeln('maw2_str_insert.exe input.scr output.scr' + #10#13 + 'Рядом с .scr файлом должен лежать .xml!');
      Exit;
    end;

    LatinAlphabet := ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
                      'P','Q','R','S','T','U','V','W','X','Y','X','a','b','c','d',
                      'e','f','g','h','i','j','k','l','m','n','o','p','q','r','s',
                      't','u','v','w','x','y','z'];
    Digits := ['0','1','2','3','4','5','6','7','8','9'];
    AnotherChars := ['_', '"', '.', ',', ' ', ':', ';', '!', '?', '&', '-', #39];

    try
      //открываем старый скрипт для чтения
      ScrFile := TFileStream.Create(ParamStr(1), fmOpenRead);
      //создаем поток в ОЗУ для нового скрипта
      NewScrMem := TMemoryStream.Create;

      //грузим базу с переводом
      XmlFile := TNativeXml.Create;
      XmlFile.LoadFromFile(ChangeFileExt(ParamStr(1), '.xml'));

      //проверяем скрипт ли в первом параметром
      if not IsThisScript(ScrFile) then begin
        Writeln('Это не скрипт.');
        Exit;
      end;

      //создаем список для меток с заданным способом сравнения
      LabelComparer := TLabelComparer.Create;
      LabelList := TLabelList<TLabel>.Create(LabelComparer);

      //парсим таблицу меток
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

      //сортируем метки
      LabelList.Sort;
      //создаем список правок
      FixList := TList<TFix>.Create;
      //вставляем текст
      InsertText(ScrFile, XmlFile, NewScrMem);
      //освобождаем базу перевода
      FreeAndNil(XmlFile);
      //вычисляем поправки
      CalculateLabelFix;
      //правим метки
      FixLabel(NewScrMem);
      //освобождаем список меток
      FreeAndNil(FixList);
      //сохраняем новый скрипт в файл
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
