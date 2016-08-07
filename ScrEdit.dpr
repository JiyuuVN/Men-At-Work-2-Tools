program ScrEdit;

{$APPTYPE CONSOLE}

{$R *.res}

// 1. Отыскать строки, сохранить, включая пролог и смещение
// 2. По прологам рассортировать строки по типу: заголовки, основной текс,
// операторов не связанных с выводом текстовых данных, метки
// 3. Исключить из спика те строки, которые входят в третью и четвертую группы
// 4. Все заголовки отсортировать, удалить повторы и составить списки смешений
// по которым они встречаются
// Сохранить всё в файл (json)

{$REGION 'Известные косяки'}
  // 1. (испр.) Не знает об опкоде $19 (case of label), поэтому метки переходов попадают
  // в список диалогов.
  // 1.1. (испр.) Если меток две, то первая метка интерпретируется, как заголовок.
  // 2. (испр.) Не знает о том, что опкод $11 кроме названия скрипта содержит имя метки,
  // поэтому название метки попадает в список диалогов.
  // 3. (испр.) Некорректно читала строки записанные не латиницей.
  // 4. (част. испр.) Чтение строк привязано к CP 1251.
{$ENDREGION}
// TODO: Вероятно стоит сократить пролог до 2х байт, т.к. не всегда перед опкодом стоит байт 00 (част. испр.)
// TODO: Длинные строки вставляются, как есть. Стоит сделать разбивку на куски по размеру текстовой области.

uses
  System.SysUtils,
  System.Classes,
  System.Character,
  ScrEdit.Types in 'ScrEdit.Types.pas',
  ScrEdit.Parser in 'ScrEdit.Parser.pas',
  ScrEdit.Parser.MultyMap in 'ScrEdit.Parser.MultyMap.pas',
  Export.JSON in 'Export.JSON.pas',
  UGastown,
  ScrEdit.Patcher in 'ScrEdit.Patcher.pas',
  Import.JSON in 'Import.JSON.pas';

function IsScr(body: TStream): Boolean;
var
  signature: Cardinal;
begin
  body.ReadBuffer(signature, 4);
  Result := signature = scrSignature;
end;

procedure ExtractStringsFromScr(const scr, output: string);
var
  scrFile: TMemoryStream;
  scrStrings: TScrStrings;
begin
  if FileExists(scr) then
  begin
    scrFile := TMemoryStream.Create;
    try
      scrFile.LoadFromFile(scr);
      if IsScr(scrFile) then
      begin
        scrStrings := ParseScr(scrFile);
        ExportLocStringsToJSON(scrStrings, output);
      end;
    finally
      scrFile.Free;
    end;
  end else
    raise EFileNotFoundException.Create(scr);
end;

procedure PatchScript(const patch, scr, output: string);
var
  scrFile: TMemoryStream;
  patchedScr: TMemoryStream;
  scrStrings: TScrStrings;
begin
  if FileExists(scr) then
  begin
    scrFile := TMemoryStream.Create;
    try
      scrFile.LoadFromFile(scr);
      patchedScr := TMemoryStream.Create;
      try
        scrStrings := ImportLocStringsFromJSON(patch);
        if IsScr(scrFile) then
        begin
          PatchScr(scrStrings, scrFile, patchedScr);
          patchedScr.SaveToFile(output);
        end;
      finally
        patchedScr.Free;
      end;
    finally
      scrFile.Free;
    end;
  end;
end;

var
  fileName: string;
  outFileName: string;
  patchFileName: string;
  params: TParameters;

procedure CheckParams;
begin
  params := Parse([
    BooleanParam('extract', 'Extract localizable strings from scr file.'),
    BooleanParam('import', 'Import localized strings into scr file.'),
    FileParam('scr', 'Script file.', '', feMustExist, fwMayBeWritable, isRequired),
    FileParam('patch', 'File with localized strings.', '', feMayExist, fwMayBeWritable, notRequired),
    FileParam('output', 'Output file.', '', feMayExist, fwMayBeWritable, notRequired)
  ]);
end;

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
    CheckParams;
    if Assigned(params) then
    begin
      fileName := params.Parameters['scr'].AsString;
      if params.Parameters['extract'].AsBoolean then
      begin
        outFileName := params.Parameters['output'].AsString;
        if outFileName = '' then
          outFileName := ChangeFileExt(fileName, '.json');
        ExtractStringsFromScr(fileName, outFileName);
      end;
      if params.Parameters['import'].AsBoolean then
      begin
        outFileName := params.Parameters['output'].AsString;
        if outFileName = '' then
          outFileName := ExtractFileName(fileName) + '_patched.scr';

        patchFileName := params.Parameters['patch'].AsString;
        if patchFileName = '' then
          patchFileName := ChangeFileExt(fileName, '.json');
        PatchScript(patchFileName, fileName, outFileName);
      end;
    end;
//    ExtractStringsFromScr('e:\D(Games)\Games\Men at Work! 2\scr\Script\H_Mena.scr', '');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ReadLn;
    end;
  end;
end.
