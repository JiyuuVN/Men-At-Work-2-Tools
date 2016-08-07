unit ScrEdit.Parser.MultyMap;

interface

uses
  System.SysUtils,
  ScrEdit.Types,
  Collections.MultiMaps;

procedure CreateMultyMap;
procedure FreeMultyMap;
procedure AddHeaderOffset(header: string; offset: Cardinal);
function GetHeaderOffsetMap: TArray<TScrHeaderString>;

implementation

var
  map: TMultiMap<string, Cardinal>;

procedure CreateMultyMap;
begin
  map := TMultiMap<string, Cardinal>.Create;
end;

procedure FreeMultyMap;
begin
  FreeAndNil(map);
end;

procedure AddHeaderOffset(header: string; offset: Cardinal);
begin
  map.Add(header, offset);
end;

function GetHeaderOffsetMap: TArray<TScrHeaderString>;
var
  list: TArray<TScrHeaderString>;
  keys: TArray<string>;
  key: string;
  i: Integer;
begin
  keys := map.Keys.ToArray;
  SetLength(list, Length(keys));
  i := 0;
  for key in map.Keys.ToArray do
  begin
    list[i].data.value := key;
    list[i].offsets := map.Items[key].ToArray;
    Inc(i);
  end;

  Result := list;
end;

end.
