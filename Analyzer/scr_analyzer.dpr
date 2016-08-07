program scr_analyzer;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  System.Character,
  Analyze.PosibleOperatorsSearch in 'Analyze.PosibleOperatorsSearch.pas',
  Analyze.PosibleStrings in 'Analyze.PosibleStrings.pas';

procedure AnalyzeScr(scr: string; analyzeType: string);
var
  scrBody: TFileStream;
  results: TStringList;
  outputFileName: string;
begin
  outputFileName := ExtractFileName(scr) + '_' + analyzeType + '.ar';

  scrBody := TFileStream.Create(scr, fmOpenRead);
  try
    results := TStringList.Create;
    try
      if analyzeType = 'pops' then
        Pops(scrBody, results);
      if analyzeType = 'postr' then
        Postr(scrBody, results);
    finally
      results.SaveToFile(ExtractFilePath(scr) + outputFileName);
      FreeAndNil(results);
    end;
  finally
    FreeAndNil(scrBody);
  end;
end;

var
  scrName: string;
  analyzeType: string;
begin
  try
    if ParamCount = 2 then
    begin
      analyzeType := ParamStr(1);
      scrName := ParamStr(2);
      AnalyzeScr(scrName, analyzeType);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
