unit Export.JSON;

interface

uses
  System.SysUtils,
  ScrEdit.Types,
  System.Classes,
  superobject;
  
procedure ExportLocStringsToJSON(const scrStrs: TScrStrings; const fileName: string);

implementation

type
  TItemConverter<SrcType, DestType> = reference to function(item: SrcType): DestType;

  TArrayProcessUtils = class
  public
    class function Convert<SrcType, DestType>(list: TArray<SrcType>; converter: TItemConverter<SrcType,DestType>): TArray<DestType>; static;
  end;

procedure ExportLocStringsToJSON(const scrStrs: TScrStrings; const fileName: string);

  function StrOffsetLength(offset: Cardinal; len: Integer): string;
  begin
    Result := IntToHex(offset, 8) + ';' + IntToHex(len, 8);
  end;

  procedure AddJsonArray(const name: string; parent: ISuperObject); inline;
  begin
    parent.O[name] := SO('[]');
  end;

  procedure AddCardinalArray(const name: string; const values: TArray<Cardinal>; parent: ISuperObject);{ inline;}
  var
    item: Cardinal;
  begin
    parent.O[name] := SO('[]');
    for item in values do
      parent.A[name].Add(item);
  end;

  procedure AddStrings(const name: string; const values: TScrLocStrings; parent: ISuperObject);{ inline;}
  var
    item: TScrLocString;
  begin
    parent.O[name] := SO('[]');
    for item in values do
      parent.A[name].Add(item.value);
  end;
  
var
  json: ISuperObject;
  output: TStringList;
  i, j: Integer;
  offsLenStr: string;
  jChooseDlg: ISuperObject;
  sizes: TArray<Cardinal>;
begin
  json := TSuperObject.Create;

  // экспорируем диалоги
  json.O['Dialogs'] := SO('[]');
  for i := 0 to Length(scrStrs.dlgStrings) - 1 do
  begin
    json.A['Dialogs'].Add(SO);
    offsLenStr := StrOffsetLength(scrStrs.dlgStrings[i].offset, Length(scrStrs.dlgStrings[i].data.value));
    json.A['Dialogs'].O[i].S[offsLenStr] := scrStrs.dlgStrings[i].data.value;
  end;

  // экспортируем заголовки
  json.O['Headers'] := SO('[]');
  for i := 0 to Length(scrStrs.headers) - 1 do
  begin
    json.A['Headers'].Add(SO);
    json.A['Headers'].O[i].I['size'] := Length(scrStrs.headers[i].data.value);
    AddCardinalArray('offsets', scrStrs.headers[i].offsets, json.A['Headers'].O[i]);
    json.A['Headers'].O[i].S['string'] := scrStrs.headers[i].data.value;
  end;

  // экспортируем выборы
  AddJsonArray('PlayerInput', json);
  for i := 0 to Length(scrStrs.chooseDlg) - 1 do
  begin
    jChooseDlg := SO;
    jChooseDlg.I['offset'] := scrStrs.chooseDlg[i].offset;
    AddStrings('choices', scrStrs.chooseDlg[i].choices, jChooseDlg);

    SetLength(sizes, Length(scrStrs.chooseDlg[i].choices));
    for j := 0 to Length(sizes) - 1 do
      sizes[j] := Length(scrStrs.chooseDlg[i].choices[j].value);
    AddCardinalArray('sizes', sizes, jChooseDlg);

    json.A['PlayerInput'].Add(jChooseDlg);
  end;

  output := TStringList.Create;
  try
    output.Add(json.AsJSon(True, False));
    output.SaveToFile(fileName);
  finally
    output.Free;
  end;
end;

{ TArrayProcessUtils }

class function TArrayProcessUtils.Convert<SrcType, DestType>(
  list: TArray<SrcType>; converter: TItemConverter<SrcType,DestType>): TArray<DestType>;
var
  newList: TArray<DestType>;
  i: Integer;
begin
  SetLength(newList, Length(list));
  for i := 0 to Length(list) - 1 do
    newList[i] := converter(list[i]);
  Result := newList;
end;

end.
