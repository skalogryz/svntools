program svndecoratedump;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, svndumptools
  { you can add units after this };

procedure ReadRewrite(const srcFn: string);
var
  dstFn : String;
  rdr   : TSVNDumpRead;
  fs    : TFileStream;
  dst   : TFileStream;
  wr    : TSVNDumpWrite;
  p     : Int64;
begin
  fs := TFileStream.Create(srcFn, fmOpenRead or fmShareDenyNone);
  dst := TFileStream.Create(srcFn+'.rewrite', fmCreate);
  rdr := TSVNDumpRead.Create(fs);
  wr := TSVNDumpWrite.Create(dst);
  try
    if not rdr.Next then Exit;

    wr.WriteHeader(rdr.version, rdr.uuid);
    repeat

      if rdr.found = dsRevision then begin
        writeln(rdr.revNum);
        wr.WriteRevision(rdr.revNum, rdr.revProp);
      end else begin
        writeln('  ',rdr.nodeInfo.path);
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

begin
  try
    if ParamCount=0 then begin
      writeln('please specify dump file');
      Exit;
    end;
    ReadRewrite(ParamStr(1));
  except
    on e: exception do begin
      writeln(stderr, 'error: ');
      writeln(stderr, e.message);
      ExitCode :=1;
    end;
  end
end.

