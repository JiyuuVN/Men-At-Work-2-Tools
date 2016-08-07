unit ScrEdit.Parser;

interface

{.$DEFINE LOGGING}

uses
  {$IFDEF LOGGING}
  CodeSiteLogging,
  {$ENDIF}
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.Character,
  System.Generics.Collections,
  Collections.Lists,
  ScrEdit.Parser.MultyMap,
  ScrEdit.Types;

function ParseScr(body: TStream; enc: TEncoding = nil): TScrStrings;

// Вынесен в интерфейс, потому что это единственная функция,
// которая общая для парсера и патчера.
function ParseJumpTable(body: TStream): TArray<TScrLabelData>;

implementation

const
  // за этими опкодами тоже следуют строки, но они нелокализуемые
  RemovableOpCodes: set of Byte = [$01, $04, $05, $11, $1e, $25, $26];

type
  TPredicate<T> = reference to function(v: T): Boolean;

var
  scrEncoding: TEncoding;

function AnsiCharToChar(c: AnsiChar): Char; forward;

function ReadCustomStringFromStream(stream: TStream; stopCondition: TPredicate<Char>) : string;
const
  STRBUF_SIZE = 1024;

var
  c: AnsiChar;
  uc: Char;
  strBuf: TBytes;
  strPos: Integer;
begin
  SetLength(strBuf, STRBUF_SIZE);
  strPos := -1;
  repeat
    Inc(strPos);
    stream.ReadBuffer(c, 1);

    if strPos > Length(strBuf) then
      SetLength(strBuf, Length(strBuf) + STRBUF_SIZE);

    strBuf[strPos] := Byte(c);
    uc := AnsiCharToChar(c);
  until stopCondition(uc) or (stream.Position >= stream.Size);

  Result := scrEncoding.GetString(strBuf, 0, strPos)
end;

function ReadStringFromStream(stream: TStream): string;
var
  stopCondition: TPredicate<Char>;
begin
  stopCondition :=
    function(v: Char): Boolean
    begin
      Result := not (TCharacter.IsLetterOrDigit(v) or TCharacter.IsPunctuation(v)
        or (v = ' ') or (v = '+'));
    end;

  Result := ReadCustomStringFromStream(stream, stopCondition);
end;

function ReadLabelFromStream(stream: TStream): string;
var
  stopCondition: TPredicate<Char>;
begin
  stopCondition :=
    function(v: Char): Boolean
    begin
      Result := not (TCharacter.IsLetterOrDigit(v) or (v = '_'));
    end;

  Result := ReadCustomStringFromStream(stream, stopCondition);
end;

function SeekForString(stream: TStream): Boolean;
var
  c: AnsiChar;
  uc: Char;
  stringFound: Boolean;
  streamSize: Int64;
begin
  c := #0;
  streamSize := stream.Size;
  stringFound := False;
  while (stream.Position < streamSize) and not stringFound do
  begin
    stream.ReadBuffer(c, 1);
    uc := AnsiCharToChar(c);
    stringFound := TCharacter.IsLetterOrDigit(uc) or TCharacter.IsPunctuation(uc) or (uc = ' ') or (uc = '+');
  end;
  if stringFound then
    stream.Seek(-1, soCurrent);
  Result := stringFound;
end;

// Ищет в потоке ближайшее вхождение опкода с кодом равным opCode и устанавливает
// указатель потока на него. Если опкод не найдет, возвращает False.
function SeekForOpCode(opCode: Byte; stream: TStream): Boolean;
var
  opCodeFound: Boolean;
  buf: array[0..2] of Byte;
  streamSize: Int64;
begin
  opCodeFound := False;
  streamSize := stream.Size;
  while (stream.Position < streamSize - SizeOf(buf)) and not opCodeFound do
  begin
    stream.ReadBuffer(buf, SizeOf(buf));
    stream.Seek(-2, soCurrent);
    opCodeFound  := (buf[0] = 0) and (buf[1] = opCode) and (buf[2] = 0);
  end;
  Result := opCodeFound;
end;

// Ищет в потоке все диалоги выборов и возвращает их описание
function ParseChooseDlg(body: TStream): TArray<TScrChooseDlg>;
var
  list: TList<TScrChooseDlg>;
  dlgStr: TScrChooseDlg;
  strCount: Byte;
  i: Integer;
  tempStr: string;
begin
  list := TList<TScrChooseDlg>.Create;
  try
    while SeekForOpCode($12, body) do
    begin
      body.Seek(2, soCurrent);
      body.ReadBuffer(strCount, 1);
      body.Seek(1, soCurrent);
      SetLength(dlgStr.choices, strCount);
      dlgStr.offset := body.Position;
      for i := 0 to strCount - 1 do
      begin
        tempStr := ReadStringFromStream(body);
        if Length(tempStr) > 2 then
          dlgStr.choices[i].value := tempStr
        else
          Break;
      end;

      if i = strCount then
        list.Add(dlgStr);
    end;

    Result := list.ToArray;
  finally
    FreeAndNil(list);
  end;
end;

function ParseLabelCase(body: TStream): TArray<Integer>;
var
  list: TList<Integer>;
  caseCount: Byte;
  countBefore: Integer;
  lbl: string;
  offset: Integer;
begin
  list := TList<Integer>.Create;
  try
    while SeekForOpCode($19, body) do
    begin
      // пропускаем сам опкод и разделитель
      body.Seek(2, soCurrent);
      // следом идет кол-во вариантов...
      body.ReadBuffer(caseCount, 1);
      // ...и разделитель
      body.Seek(1, soCurrent);

      countBefore := list.Count;
      repeat
        offset := body.Position;
        lbl := ReadLabelFromStream(body);
        if (lbl <> '') and (Length(lbl) > 2) then
          list.Add(offset)
        else
          break;
        Dec(caseCount);
      until caseCount = 0;

      // если caseCount > 0, значит мы не дошли до конца, потому что
      // это скорее всего было ложное срабатывание
      if caseCount > 0 then
        while list.Count > countBefore do
          list.RemoveAt(list.Count - 1);
    end;

    Result := list.ToArray;
  finally
    FreeAndNil(list);
  end;
end;

// Возврашает список всех меток из таблицы переходов
function ParseJumpTable(body: TStream): TArray<TScrLabelData>;

  procedure ReadLabel(script: TStream; var value: TScrLabelData); inline;
  begin
    value.scrOffset := script.Position;
    value.name := ReadLabelFromStream(script);
    if value.name <> '' then
      script.ReadBuffer(value.addr, 4);
  end;

var
//  lbl: string;
  lbl: TScrLabelData;
  labels: TList<TScrLabelData>;
  {$IFDEF LOGGING}
  parsePos: Integer;
  buf: array[0..3] of AnsiChar;
  {$ENDIF}
begin
  labels := TList<TScrLabelData>.Create;
  try
    ReadLabel(body, lbl);
    while lbl.name <> '' do
    begin
      labels.Add(lbl);
      ReadLabel(body, lbl);
      {$IFDEF LOGGING}
      parsePos := body.Position;
      body.Position := lbl.addr;
      body.ReadBuffer(buf, 4);
      body.Position := parsePos;
      CodeSite.Send(lbl, buf);
      {$ENDIF}
    end;

    Result := labels.ToArray;
  finally
    labels.Free;
  end;
end;

// Ищет все потенциальные строки в потоке и запоминает их прологи
function ParseCodeSection(body: TStream): TArray<TScrStringData>;
var
  s: TScrStringData;
  strData: string;
  strList: TList<TScrStringData>;
begin
  strList := TList<TScrStringData>.Create;
  try
    while SeekForString(body) do
    begin
      body.Seek(-SizeOf(TScrStringProlog), soFromCurrent);
      body.ReadBuffer(s.prolog, SizeOf(TScrStringProlog));

      s.offset := body.Position;
      strData := ReadStringFromStream(body);
      s.data := strData;

      if Length(s.data) > 2 then
        strList.Add(s);
    end;

    Result := strList.ToArray;
  finally
    FreeAndNil(strList);
  end;
end;

function IsHeader(prolog: TScrStringProlog): Boolean;
begin
  Result := (prolog[0] = 0) and (prolog[1] = $02) and (prolog[2] = 0);
end;

// Удаляет из списка строк те, что являются метками.
function RemoveLabels(list: TArray<TScrStringData>; const labels: TArray<TScrLabelData>): TArray<TScrStringData>;

  function IsLabel(s: string; const labels: TArray<TScrLabelData>): Boolean; inline;
  var
    lbl: TScrLabelData;
    lowerS: string;
  begin
    Result := False;
    lowerS := LowerCase(s);
    for lbl in labels do
    begin
      if lowerS = LowerCase(lbl.name) then
        Exit(True);
    end;
  end;

var
  newList: TList<TScrStringData>;
  strData: TScrStringData;
begin
  newList := TList<TScrStringData>.Create;
  try
    for strData in list do
    begin
      // метки могут совпадать с именами персонажей
      if IsHeader(strData.prolog) or (not IsLabel(strData.data, labels)) then
        newList.Add(strData);
    end;
    Result := newList.ToArray;
  finally
    FreeAndNil(newList);
  end;
end;

// Удаляет из найденных строк те, что являются строковыми параметрами опкодов,
// не имеющих отношения к выводу текста на экран.
function RemoveOpCodeParameters(list: TArray<TScrStringData>): TArray<TScrStringData>;

  function IsRemovable(str: TScrStringData): Boolean; inline;
  begin
    Result := {(str.prolog[0] = 0) and }(str.prolog[1] in RemovableOpCodes) and (str.prolog[2] = 0)
  end;

var
  strData: TScrStringData;
  newList: TList<TScrStringData>;
  skipCallSecondParam: Boolean;
begin
  newList := TList<TScrStringData>.Create;
  try
    skipCallSecondParam := False;
    for strData in list do
    begin
      // пропускаем метку
      if skipCallSecondParam then
      begin
        skipCallSecondParam := False;
        Continue;
      end;

      if not IsRemovable(strData) then
        newList.Add(strData)
      else
      // Опкод вызова другого скрипта имеет два строковых параметра: имя файла и метки
        skipCallSecondParam := (strData.prolog[1] = $11);
    end;

    Result := newList.ToArray;
  finally
    FreeAndNil(newList);
  end;
end;

// Удаляет из списка строк те, что являются вариантами выбора пути
function RemoveChooseDlgStrings(list: TArray<TScrStringData>; chooseDlgs: TArray<TScrChooseDlg>): TArray<TScrStringData>;

  function IsChooseString(const str: string; const chooseDlgs: TArray<TScrChooseDlg>): Boolean; inline;
  var
    chooseDlg: TScrChooseDlg;
    chooseStr: TScrLocString;
  begin
    Result := False;
    for chooseDlg in chooseDlgs do
      for chooseStr in chooseDlg.choices do
      begin
        if str = chooseStr.value then
          Exit(True);
      end;
  end;

var
  newList: TList<TScrStringData>;
  strData: TScrStringData;
begin
  newList := TList<TScrStringData>.Create;
  try
    for strData in list do
    begin
      if not IsChooseString(strData.data, chooseDlgs) then
        newList.Add(strData);
    end;

    Result := newList.ToArray;
  finally
    FreeAndNil(newList);
  end;
end;

function RemoveLabelCase(list: TArray<TScrStringData>; caseLabelAddr: TArray<Integer>): TArray<TScrStringData>;
var
  strData: TScrStringData;
  newList: TList<TScrStringData>;
  clIdx: Integer;
begin
  newList := TList<TScrStringData>.Create;
  try
    for strData in list do
    begin
      if not TArray.BinarySearch<Integer>(caseLabelAddr, strData.offset, clIdx) then
        newList.Add(strData);
    end;

    Result := newList.ToArray;
  finally
    FreeAndNil(newList);
  end;
end;

// Сортирует сроки на диалоги и заголовки.
function SortScrString(list: TArray<TScrStringData>):TScrStrings;
var
  dlgStrings: TList<TScrDlgString>;
  strData: TScrStringData;
  dlgString: TScrDlgString;
begin
  dlgStrings := TList<TScrDlgString>.Create;
  CreateMultyMap;
  try
    for strData in list do
    begin
      if not IsHeader(strData.prolog) then
      begin
        dlgString.data.value := strData.data;
        dlgString.offset := strData.offset;
        dlgStrings.Add(dlgString);
      end
      else
        AddHeaderOffset(strData.data, strData.offset);
    end;

    Result.dlgStrings := dlgStrings.ToArray;
    Result.headers := GetHeaderOffsetMap;
  finally
    FreeAndNil(dlgStrings);
    FreeMultyMap;
  end;
end;

// Объединяет соседние строки в одну, если те идут друг за другом.
// Причина в том, что длинные строки в скрипте дробятся на мелкие символом #0.
function MergeDlgStrings(list: TArray<TScrDlgString>): TArray<TScrDlgString>;

  function IsProlongation(value, dlgStr: TScrDlgString): Boolean;
  begin
    Result := (dlgStr.offset + Cardinal(Length(dlgStr.data.value)) + 1) = value.offset;
  end;

  procedure Merge(src: TScrDlgString; var dest: TScrDlgString); inline;
  begin
    dest.data.value := dest.data.value + ' ' + src.data.value;
  end;

var
  newList: TList<TScrDlgString>;
  dlgString: TScrDlgString;
  merged: TScrDlgString;
begin
  newList := TList<TScrDlgString>.Create;
  try
    newList.Add(list[0]);
    for dlgString in list do
    begin
      if IsProlongation(dlgString, newList.Last) then
      begin
        merged := newList.Last;
        Merge(dlgString, merged);
        newList.Items[newList.Count - 1] := merged;
      end else
        newList.Add(dlgString);
    end;
    newList.RemoveAt(0);

    Result := newList.ToArray;
  finally
    FreeAndNil(newList);
  end;
end;

var
  charBuf: TBytes;

function AnsiCharToChar(c: AnsiChar): Char;
begin
  charBuf[0] := Byte(c);
  Result := scrEncoding.GetChars(charBuf, 0, 1)[0];
end;

function ParseScr(body: TStream; enc: TEncoding = nil): TScrStrings;
var
  labels: TArray<TScrLabelData>;
  caseLblIdx: TArray<Integer>;
  chooseDlgs: TArray<TScrChooseDlg>;
  strs: TArray<TScrStringData>;
  scrStrs: TScrStrings;
  scrPos: Int64;
begin
  if Assigned(enc) then
    scrEncoding := enc
  else
    scrEncoding := TEncoding.Default;
//  SetLength(charBuf, 1);

  labels := ParseJumpTable(body);
  scrPos := body.Position;
  chooseDlgs := ParseChooseDlg(body);
  body.Position := scrPos;
  caseLblIdx := ParseLabelCase(body);
  body.Position := scrPos;
  strs := ParseCodeSection(body);
  strs := RemoveOpCodeParameters(strs);
  strs := RemoveLabels(strs, labels);
  strs := RemoveLabelCase(strs, caseLblIdx);
  strs := RemoveChooseDlgStrings(strs, chooseDlgs);
  scrStrs := SortScrString(strs);
  scrStrs.dlgStrings := MergeDlgStrings(scrStrs.dlgStrings);
  scrStrs.chooseDlg := chooseDlgs;
  Result := scrStrs;

  FreeAndNil(enc);
end;

initialization
  SetLength(charBuf, 1);
  scrEncoding := TEncoding.Default;

end.
