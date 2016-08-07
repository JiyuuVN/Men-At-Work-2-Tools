unit Analyze.PosibleOperatorsSearch;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

procedure Pops(scr: TStream; res: TStringList);

implementation


// составляет список всех потенциальных операторов подходящих под шаблон \x00\xOP\x00
procedure Pops(scr: TStream; res: TStringList);
var
  ops: TList<Byte>;
  buf: array[0..2] of Byte;
  pop: Byte;
begin
  ops := TList<Byte>.Create;
  try
    scr.Position := 0;
    while scr.Position < scr.Size - 3 do
    begin
      scr.ReadBuffer(buf, 3);
      if (buf[0] = 0) and (buf[2] = 0) and (buf[1] <> 0) then
        if not ops.Contains(buf[1]) then
          ops.Add(buf[1]);
    end;

    ops.Sort;
    for pop in ops do
    begin
      res.Add(IntToHex(pop, 2));
    end;

  finally
    FreeAndNil(ops);
  end;
end;

end.
