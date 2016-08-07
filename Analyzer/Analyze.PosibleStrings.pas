unit Analyze.PosibleStrings;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Character;

procedure Postr(scr: TStream; res: TStringList);

implementation

procedure Postr(scr: TStream; res: TStringList);
var
  c: Char;
  b: Byte;
  buf: string;
begin
  scr.Position := 0;
  while scr.Position < scr.Size do
  begin
    scr.ReadBuffer(b, 1);
    c := Char(b);
    if TCharacter.IsLetterOrDigit(c) or TCharacter.IsPunctuation(c) or (c = ' ') then
      buf := buf + c;
    if c = #0 then
    begin
      if Length(buf) > 2 then
        res.Add(buf);
      buf := '';
    end;
  end;
end;

end.
