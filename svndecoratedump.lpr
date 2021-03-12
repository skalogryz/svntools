program svndecoratedump;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, svndumptools
  { you can add units after this };

type
  TFileInfo = class(TObject)
    fileName : string;
    revision : Integer;
  end;

type

  { TDecorationTask }

  TDecorationTask = class(TObject)
  public
    remove : TList;
    dumpLog: Boolean;
    procedure AddToRemove(const fn: string; rev: integer);
    procedure AddToRemove(const fn: string);

    function CanWriteNode(rev: integer; nodeInfo: TNodeInfo): Boolean;

    constructor Create;
    destructor Destroy; override;
  end;

  TInputOut = record
    inputFile : string;
    outFile   : string;
  end;


procedure ReadRewrite(const srcFn, dstFn: string; dt: TDecorationTask);
var
  rdr   : TSVNDumpRead;
  fs    : TFileStream;
  dst   : TFileStream;
  wr    : TSVNDumpWrite;
  p     : Int64;
  r     : Int64;
  err   : Integer;
begin
  fs := TFileStream.Create(srcFn, fmOpenRead or fmShareDenyNone);
  dst := TFileStream.Create(dstFn, fmCreate);
  rdr := TSVNDumpRead.Create(fs);
  wr := TSVNDumpWrite.Create(dst);
  r:=0;
  try
    if not rdr.Next then Exit;

    wr.WriteHeader(rdr.version, rdr.uuid);
    repeat

      if rdr.found = dsRevision then begin
        Val(rdr.revNum, r, err);
        if dt.dumpLog then writeln(rdr.revNum);
        wr.WriteRevision(rdr.revNum, rdr.revProp);
      end else begin
        if not dt.CanWriteNode(r, rdr.nodeInfo) then Continue;

        if dt.dumpLog then writeln('  ',rdr.nodeInfo.path);
        p:=fs.Position;
        wr.WriteNode(
          rdr.nodeInfo
         ,rdr.propOfs, rdr.propLen, fs
         ,rdr.txtCntOfs, rdr.txtCntLen, fs
        );
        fs.Position:=p;
      end;
    until not rdr.Next;

  finally
    rdr.Free;
    fs.Free;
    dst.Free;
    wr.Free;
  end;
end;

{ TDecorationTask }

procedure TDecorationTask.AddToRemove(const fn: string; rev: integer);
var
  f : TFileInfo;
begin
  f := TFileInfo.Create;
  f.fileName := fn;
  f.revision := rev;
  remove.Add(f);
end;

procedure TDecorationTask.AddToRemove(const fn: string);
var
  i : integer;
  f  : string;
  rev : integer;
  err : integer;
begin
  f:=fn;
  i:=Pos('@', f);
  rev :=-1;
  if i>0 then begin
    Val( Trim(Copy(f, i+1, length(f))), rev, err);
    if err<>0 then rev:=-1;
    f:=Copy(f, 1, i-1);
  end else
    rev:=1;
  AddToRemove(f, rev);
end;

function TDecorationTask.CanWriteNode(rev: integer; nodeInfo: TNodeInfo): Boolean;
var
  i : integer;
  fi : TFileInfo;
begin
  for i:=0 to remove.Count-1 do begin
    fi := TFileInfo(remove[i]);
    if (nodeInfo.path = fi.fileName) and ((fi.revision<0) or (fi.revision = rev))
    then begin
      Result := false;
      Exit;
    end;
  end;
  Result := true;
end;

constructor TDecorationTask.Create;
begin
  inherited Create;
  dumpLog:=true;
  remove:=Tlist.Create;
end;

destructor TDecorationTask.Destroy;
var
  i : integer;
begin
  for i:=0 to remove.Count-1 do
    TobjecT(remove[i]).Free;
  remove.Free;
  inherited Destroy;
end;

procedure ParseParams(var inout: TInputOut; dt: TDecorationTask);
var
  i : integer;
  s : string;
  ls : string;
begin
  i:=1;
  while i<=ParamCount do begin
    s := ParamStr(i);
    ls := AnsiLowerCase(s);
    if ls = '-r' then begin
      inc(i);
      if i<=ParamCount then
        dt.AddToRemove(ParamStr(i));
    end else if ((ls = '-q') or (ls = '--quite')) then begin
      dt.dumpLog := false;
    end else if ((ls = '-o') or (ls = '--out')) then begin
      inc(i);
      if i<=ParamCount then
        inout.outFile := ParamStr(i);
    end else
      inout.inputFile := s;
    inc(i);
  end;

  if (inout.outFile = '') and (inout.inputFile<>'') then
    inout.outFile := inout.inputFile+'.rewrite';

end;

procedure DumpHelp;
begin
  writeln('-r filename[@revsion] = remove the file, followed by revision number. If revision number is omitted All entries of the file is exlcuded');
  writeln('-q - quite mode, no output');
  writeln('-o - the name of the output file path');
end;

var
  inout: TInputOut;
  dt : TDecorationTask;
begin
  try
    if ParamCount=0 then begin
      writeln('please specify dump file');
      DumpHelp;
      Exit;
    end;
    inout.inputFile:='';
    inout.outFile := '';
    dt := TDecorationTask.Create;
    try
      ParseParams(inout, dt);
      ReadRewrite(inout.inputFile, inout.outFile, dt);
    finally
      dt.Free;
    end;
  except
    on e: exception do begin
      writeln(stderr, 'error: ');
      writeln(stderr, e.message);
      ExitCode :=1;
    end;
  end
end.

