unit Import.JSON;

interface

uses
  System.SysUtils, System.StrUtils, ScrEdit.Types, superobject;

function ImportLocStringsFromJSON(const fileName: string): TScrStrings;

implementation

function ImportLocStringsFromJSON(const fileName: string): TScrStrings;
var
  json, hdr, choose: ISuperObject;
  dlg: TSuperAvlEntry;
  scrStrings: TScrStrings;
  strOffset, strLength: Cardinal;
  strOffsetLng: string;
  i, j: Integer;
begin
  json := TSuperObject.ParseFile(fileName, False);

  // импортируем строчки диалогов
  SetLength(scrStrings.dlgStrings, json.A['Dialogs'].Length);
  for i := 0 to json.A['Dialogs'].Length - 1 do
    for dlg in json.A['Dialogs'].O[i].AsObject do
    begin
      strOffsetLng := dlg.Name;
      strOffset := StrToInt('$' + LeftStr(strOffsetLng, 8));
      strLength := StrToInt('$' + RightStr(strOffsetLng, 8));

      scrStrings.dlgStrings[i].data.value := dlg.Value.AsString;
      scrStrings.dlgStrings[i].data.origLen := strLength;
      scrStrings.dlgStrings[i].offset := strOffset;
    end;

  // импортируем заголовки
  SetLength(scrStrings.headers, json.A['Headers'].Length);
  i := 0;
  for hdr in json['Headers'] do
  begin
    scrStrings.headers[i].data.value := hdr['string'].AsString;
    scrStrings.headers[i].data.origLen := hdr['size'].AsInteger;
    SetLength(scrStrings.headers[i].offsets, hdr['offsets'].AsArray.Length);
    for j := 0 to hdr['offsets'].AsArray.Length - 1 do
      scrStrings.headers[i].offsets[j] := hdr['offsets'].AsArray.I[j];
    Inc(i);
  end;

  // импортируем выборы
  SetLength(scrStrings.chooseDlg, json.A['PlayerInput'].Length);
  i := 0;
  for choose in json['PlayerInput'] do
  begin
    scrStrings.chooseDlg[i].offset := choose['offset'].AsInteger;

    SetLength(scrStrings.chooseDlg[i].choices, choose['choices'].AsArray.Length);
    for j := 0 to choose['choices'].AsArray.Length - 1 do
    begin      
      scrStrings.chooseDlg[i].choices[j].value := choose['choices'].AsArray.S[j];
      scrStrings.chooseDlg[i].choices[j].origLen := choose['sizes'].AsArray.I[j];
    end;
  
    Inc(i);
  end;

  Result := scrStrings;
end;

end.
