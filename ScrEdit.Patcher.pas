unit ScrEdit.Patcher;

interface

uses
  System.SysUtils, System.Classes, ScrEdit.Types,{ System.Generics.Collections,}
  Collections.Dictionaries, ScrEdit.Parser;

procedure PatchScr(const data: TScrStrings; origScript, patchedScript: TStream);

implementation

type
  TOffset = Cardinal;
  TScrLocAString = record
    value: AnsiString;
    origLen: Cardinal;
  end;
  TPatchData = TSortedDictionary<TOffset, TScrLocAString>;

procedure PreparePatch(const locData: TScrStrings; patchData: TPatchData);

  // Смысл в том, чтобы избажать на каждой итерации всей сопроводительной работы
  // по созданию новой строки и оставить её только на последний этап.
  function MergeStrings(src: TScrLocStrings; out origLen: Cardinal): string;
  var
    strBuf: TStringStream;
    ls: TScrLocString;
  begin
    strBuf := TStringStream.Create;
    try
      origLen := 0;
      for ls in src do
      begin
        strBuf.WriteString(ls.value);
        strBuf.WriteString(#0);
        origLen := origLen + ls.origLen + 1;
        Result := strBuf.DataString;
      end;
    finally
      strBuf.Free;
    end;
  end;

var
  dlgString: TScrDlgString;
  hdrString: TScrHeaderString;
  chsString: TScrChooseDlg;
  hdrOffset: Cardinal;
  mergedChoose: String;
  locAnsiString: TScrLocAString;
  origLen: Cardinal;
begin
  for dlgString in locData.dlgStrings do
  begin
    locAnsiString.value := AnsiString(dlgString.data.value);
    locAnsiString.origLen := dlgString.data.origLen;
    patchData.Add(dlgString.offset, locAnsiString);
  end;

  for hdrString in locData.headers do
    for hdrOffset in hdrString.offsets do
    begin
      locAnsiString.value := AnsiString(hdrString.data.value);
      locAnsiString.origLen := hdrString.data.origLen;
      patchData.Add(hdrOffset, locAnsiString);
    end;

  for chsString in locData.chooseDlg do
  begin
    mergedChoose := MergeStrings(chsString.choices, origLen);
    locAnsiString.value := AnsiString(mergedChoose);
    locAnsiString.origLen := origLen;
    patchData.Add(chsString.offset, locAnsiString);
  end;  
end;

type
  TStealedChunk = array[0..3] of Byte;
  TMark = Integer;

var
  stealedBytes: array of TStealedChunk;

// На основе переходов расставляет в потоке метки и запоминает оригинальное содержимое
procedure SetupJumpMarks(labels: TArray<TScrLabelData>; script: TStream);
var
  lblData: TScrLabelData;
  i: Integer;
  mark: TMark;
begin
  SetLength(stealedBytes, Length(labels));
  i := 0;
  for lblData in labels do
  begin
    script.Seek(lblData.addr, soBeginning);
    script.ReadBuffer(stealedBytes[i], SizeOf(TStealedChunk));
    mark := $FE0000EF or (Word(i) shl 8);
    script.Seek(-SizeOf(TStealedChunk), soCurrent);
    script.WriteBuffer(Mark, SizeOf(TMark));
    Inc(i);
  end;
end;

// Ищет метку в потоке.
function SearchNextMark(script: TStream; out mark: TMark): Boolean;
begin
  Result := False;
  while script.Read(mark, SizeOf(TMark)) = SizeOf(TMark) do
  begin
    Result := (mark and $FE0000EF) = $FE0000EF;
    if Result then
      Exit;
    script.Seek(-SizeOf(TMark) + 1, soCurrent);
  end;
end;

// Ищет в пропатченном потоке метки и исправляет по ним переходы.
procedure PatchJumps(var labels: TArray<TScrLabelData>; script: TStream);
var
  i: Integer;
  mark: TMark;
begin
  script.Position := 0;
  while SearchNextMark(script, mark) do
  begin
    i := (mark and $00FFFF00) shr 8;
    script.Seek(-SizeOf(TMark), soCurrent);
    labels[i].addr := script.Position;
    script.WriteBuffer(stealedBytes[i], SizeOf(TStealedChunk));
  end;
end;

// Правит таблицу переходов в скрипте.
procedure PatchJumpTable(const labels: TArray<TScrLabelData>; script: TStream);
var
  lblData: TScrLabelData;
begin
  for lblData in labels do
  begin
    script.Seek(lblData.scrOffset + Length(lblData.name) + 1, soBeginning);
    script.WriteBuffer(lblData.addr, 4);
  end;
end;

// Дано: локализованные строки и оригинальный скрипт с метками
// На выходе: скрипт с замененными строками
procedure ReplaceLocStrings(const locStrs: TPatchData; origScript, patchedScript: TStream);

  procedure WriteAsAnsi(const value: string; aStream: TStream);
  var
    ansiStr: AnsiString;
  begin
    ansiStr := AnsiString(value);
    aStream.WriteBuffer(ansiStr[1], Length(ansiStr));
  end;

var
  locStr: TScrLocAString;
  strPos: UInt32;
begin
  // 1. Встать в начало оригинального скрипта.
  // 2. Подглядеть адрес первой строки
  // 3. Скопировать всё от начала оригинального скрипта до начала строки в пропатченный скрипт
  //-----------
  // 4. Вставить в пропатченный скрипт новую строку.
  // 5. Проскочить в оригинальнос скрипте на длину оригинальной строки.
  // 6. Подглядеть адрес второй строки
  // 7. Скопировать из оригинального скрипта в пропатченный байт в кол-ве: аддр2 - (аддр1 + длина1)
  // 8. перейти к пункту 4.
  // и т.д.
  patchedScript.Position := 0;
  origScript.Position := 0;
  for strPos in locStrs.Keys do
  begin
    locStr := locStrs[strPos];
    patchedScript.CopyFrom(origScript, strPos - origScript.Position);
    patchedScript.WriteBuffer(locStr.value[1], Length(locStr.value));
    origScript.Seek(locStr.origLen, soCurrent);
  end;
  // Копируем остаток файла, который идет после последней локализуемой строки.
  patchedScript.CopyFrom(origScript, origScript.Size - origScript.Position);
end;

procedure PatchScr(const data: TScrStrings; origScript, patchedScript: TStream);
var
  patchData: TPatchData;
  lbls: TScrLabels;
begin
  patchData := TPatchData.Create;
  try
    PreparePatch(data, patchData);
    lbls := ParseJumpTable(origScript);
    SetupJumpMarks(lbls, origScript);
    // тут сборка нового скрипта из локализованных строк и оригинального кода
    ReplaceLocStrings(patchData, origScript, patchedScript);
    PatchJumps(lbls, patchedScript);
    PatchJumpTable(lbls, patchedScript);
  finally
    patchData.Free;
  end;
end;

end.
