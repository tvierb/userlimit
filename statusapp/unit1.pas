unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls;

type

  { TForm1 }

  TForm1 = class(TForm)
    Label1: TLabel;
    Shape1: TShape;
    Shape2: TShape;
    Timer1: TTimer;
    procedure Shape2Click(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private

  public

  end;

var
  Form1: TForm1;
  timeleft: Integer;
  statusfile: String;
  s: String;
  L: TStringList;
  name, value: String;
  i: Integer;
  minutes: Integer;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.Shape2Click(Sender: TObject);
begin

end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  statusfile := Concat( '/var/cache/userlimit/', GetEnvironmentVariable('USER'));
  L := TStringList.create;
  try
      L.LoadFromFile( statusfile );
      for i:=0 to L.Count-1 do begin
        name := L.Names[i];
        if name = 'timeleft' then begin
          timeleft := StrToInt( L.Values['timeleft'] );
          if timeleft < 120 then begin
            Shape1.Visible := true;
            Shape2.Visible := false;
          end
          else if timeleft <= 300  then begin
            Shape1.Visible := false;
            Shape2.Visible := true;
          end
          else begin
            Shape1.Visible := false;
            Shape2.Visible := false;
          end;
          // timeleft := StrToInt( L.Values[ 'timeleft' ] );
          minutes := Trunc(timeleft / 60);
          timeleft := timeleft - (60 * minutes);
          Label1.Caption := Concat(Format('%3.2d', [minutes]), ':', Format('%2.2d', [timeleft]));
        end;
      end;
  finally
    L.free;
  end;

end;

end.

