// MIT License
// Dmitry 'skalogryz' Boyarintsev 2020
unit svndumptools;

{$mode objfpc}{$H+}

interface

// http://svn.apache.org/repos/asf/subversion/trunk/notes/dump-load-format.txt

uses
  Classes, SysUtils;

type
  TSVNDumpStatus = (dsEof, dsVersion, dsUUID, dsRevision, dsNode, dsError);

  TNodeInfo = record
    // version 2
    path          : string; // mandatory
    kind          : string;
    action        : string; // mandatory

    text_delta    : string; // True/False // ver3  //version-3
    prop_delta    : string; // True/False // ver3  //version-3
    text_delta_base_md5  : string;                 //version-3
    text_delta_base_sha1 : string;                 //version-3

    copyfrom_rev  : string;
    copyfrom_path : string;
    text_copy_src_md5  : string;
    text_copy_src_sha1 : string;

    text_content_md5   : string;
    text_content_sha1  : string;
  end;

  { TSVNDumpRead }

  TSVNDumpRead = class(TObject)
  private
    cntLen  : Int64;
    status  : TSVNDumpStatus;
    src     : TStream;
    procedure ConsumeCommand(const cmd: string);
    procedure ConsumeKeyVal(const k, v: string);
    procedure ResetRevInfo;
    procedure ResetNodeInfo;
  public
    version : string;
    uuid    : string;

    found   : TSVNDumpStatus;
    revNum  : string;
    revProp : string;

    nodeInfo  : TNodeInfo;
    propLen   : Int64;
    txtCntLen : Int64;

    propOfs   : Int64;
    txtCntOfs : Int64;
    constructor Create(ASource: TStream);
    function Next: Boolean;
  end;

  { TSVNDumpWriter }

  TSVNDumpWrite = class(TObject)
  private
    dst : TStream;
    procedure WriteStr(const s: string);
    procedure WriteKeyVal(const key, val: string);
  public
    constructor Create(ADst: TStream);
    procedure WriteHeader(const ver, uuid: string);
    procedure WriteRevision(const revNum: string; const prop: String);
    procedure WriteNode(const n: TNodeInfo;
      const propOfs, propLen: Int64; const propStream: TStream;
      const textOfs, textLen: Int64; const textStream: TStream);
  end;

function GetSVNLine(const src: TStream; var cmd: string): Boolean;
function SplitCmd(const cmd: string; var k,v : string): Boolean;

procedure InitNodeInfo(out n: TNodeInfo);

implementation

function SplitCmd(const cmd: string; var k,v : string): Boolean;
var
  i : integer;
begin
  i:=Pos(' ', cmd);
  result :=i>0;
  if not Result then Exit;
  k:=Copy(cmd, 1, i-1);
  v:=Copy(cmd, i+1, length(cmd)-1);
end;

procedure InitNodeInfo(out n: TNodeInfo);
begin
  n.path := '';
  n.kind := '';
  n.action := '';

  n.text_delta := '';
  n.prop_delta := '';
  n.text_delta_base_md5  := '';
  n.text_delta_base_sha1 := '';

  n.copyfrom_rev  := '';
  n.copyfrom_path := '';
  n.text_copy_src_md5  := '';
  n.text_copy_src_sha1 := '';

  n.text_content_md5  := '';
  n.text_content_sha1 := '';
end;

function GetSVNLine(const src: TStream; var cmd: string): Boolean;
var
  ch  : byte;
  l   : integer;
begin
  cmd:='';
  Result:=false;
  while true do begin
    l := src.Read(ch, 1);
    if l<=0 then begin
      Exit; // error
    end;
    if (ch<>$0a) then begin
      cmd:=cmd+chr(ch)
    end else begin
      Result:=true;
      break;
    end;
  end;
end;

{ TSVNDumpWrite }

procedure TSVNDumpWrite.WriteStr(const s: string);
begin
  if length(s)>0 then begin
    dst.Write(s[1], length(s));
    dst.Writebyte($0a);
  end;
end;

procedure TSVNDumpWrite.WriteKeyVal(const key, val: string);
begin
  if (val='') or (key='') then Exit;
  dst.WriteBuffer(key[1], length(key));
  dst.WriteByte(32);
  dst.WriteBuffer(val[1], length(val));
  dst.WriteByte($0a);
end;

constructor TSVNDumpWrite.Create(ADst: TStream);
begin
  inherited Create;
  dst:=ADst;
end;

procedure TSVNDumpWrite.WriteHeader(const ver, uuid: string);
var
  b : string;
begin
  b:=ver+#$a+#$a+uuid+#$a+#$a;
  dst.Write(b[1], length(b));
end;

procedure TSVNDumpWrite.WriteRevision(const revNum: string; const prop: String);
var
  b : string;
begin
  b:=Format('Revision-number: %s'+#$a
+'Prop-content-length: %d'+#$a
+'Content-length: %d'+#$a+#$a, [revNum, length(prop), length(prop)]);
  dst.WriteBuffer(b[1], length(b));
  if length(prop)>0 then
    dst.WriteBuffer(prop[1], length(prop));
  dst.WriteByte($0a);
end;

procedure TSVNDumpWrite.WriteNode(
  const n: TNodeInfo;
  const propOfs, propLen: Int64; const propStream: TStream;
  const textOfs, textLen: Int64; const textStream: TStream);
var
  cntLen : Int64;
  l : Int64;
  writeCntLen: Boolean;
begin
  //todo: sanity check

  WriteKeyVal('Node-path:',n.path);
  WriteKeyVal('Node-kind:',n.kind);
  WriteKeyVal('Node-action:',n.action);

  WriteKeyVal('Node-copyfrom-rev:',n.copyfrom_rev);
  WriteKeyVal('Node-copyfrom-path:',n.copyfrom_path);
  WriteKeyVal('Text-copy-source-md5:',n.text_copy_src_md5);
  WriteKeyVal('Text-copy-source-sha1:',n.text_copy_src_sha1);

  // "-delta" is version 3 headers
  // Prop-delta goes before Text-delta this is how svnadmin does it, but it violates the specs.
  WriteKeyVal('Prop-delta:',n.prop_delta);
  WriteKeyVal('Text-delta:',n.text_delta);
  WriteKeyVal('Text-delta-base-md5:',n.text_delta_base_md5);
  WriteKeyVal('Text-delta-base-sha1:',n.text_delta_base_sha1);

  WriteKeyVal('Text-content-md5:',n.text_content_md5);
  WriteKeyVal('Text-content-sha1:',n.text_content_sha1);

  cntLen := 0;
  if propLen > 0 then inc(cntLen, propLen);
  if textLen > 0 then inc(cntLen, textLen);

  if propLen >= 0 then
    WriteKeyVal('Prop-content-length:', IntToStr(propLen));
  if textLen >= 0 then
    WriteKeyVal('Text-content-length:', IntToStr(textLen));
  writeCntLen := (cntLen>=0) and ((propLen>=0) or (textLen>=0));
  if writeCntLen then
    WriteKeyVal('Content-length:', IntToStr(cntLen));
  dst.WriteByte($0a);

  if propLen >0 then begin
    propStream.Position:=propOfs;
    dst.CopyFrom(propStream, propLen);
  end;
  if textLen > 0 then begin
    textStream.Position := textOfs;
    dst.CopyFrom(textStream, textLen);
  end;

  if writeCntLen then dst.WriteByte($0a);
  dst.WriteByte($0a);
end;

{ TSVNDumpRead }

procedure TSVNDumpRead.ConsumeCommand(const cmd: string);
var
  k,v : string;
begin
  if SplitCmd(cmd, k, v) then
    ConsumeKeyVal(k,v);
end;

procedure TSVNDumpRead.ConsumeKeyVal(const k, v: string);
var
  err : Integer;
begin
  if (k ='Revision-number:') then        revNum:=v
  else if (k='Content-length:') then   val(v, cntLen, err)
  else if (k='Prop-content-length:') then val(v, propLen, err)
  else if (k='Text-content-length:') then val(v, txtCntLen, err)
  else if (k='Node-path:')             then nodeInfo.path := v
  else if (k='Node-action:')           then nodeInfo.action := v
  else if (k='Node-kind:')             then nodeInfo.kind := v
  else if (k='Node-copyfrom-rev:')     then nodeInfo.copyfrom_rev := v
  else if (k='Node-copyfrom-path:')    then nodeInfo.copyfrom_path := v
  else if (k='Text-copy-source-md5:')  then nodeInfo.text_copy_src_md5 := v
  else if (k='Text-copy-source-sha1:') then nodeInfo.text_copy_src_sha1 := v
  else if (k='Text-content-md5:')      then nodeInfo.text_content_md5 := v
  else if (k='Text-content-sha1:')     then nodeInfo.text_content_sha1 := v
  // version 3
  else if (k='Text-delta:') then nodeInfo.text_delta := v
  else if (k='Prop-delta:') then nodeInfo.prop_delta := v
  else if (k='Text-delta-base-md5:') then nodeInfo.text_delta_base_md5 := v
  else if (k='Text-delta-base-sha1:') then nodeInfo.text_delta_base_sha1 := v
  ;
end;

procedure TSVNDumpRead.ResetRevInfo;
begin
  revNum := '';
  revProp := '';
end;

procedure TSVNDumpRead.ResetNodeInfo;
begin

end;

constructor TSVNDumpRead.Create(ASource: TStream);
begin
  status:=dsVersion;
  src:=ASource;
end;

function TSVNDumpRead.Next: Boolean;
var
  s : string;
begin
  if status=dsVersion then begin
    GetSVNLine(src, version);
    status:=dsUUID;
    GetSVNLine(src, s); // skip empty line
  end;
  if status = dsUUID then begin
    GetSVNLine(src, uuid);
    status:=dsRevision;
    GetSVNLine(src, s); // skip empty line
  end;

  if status = dsEof then begin
    found := dsEof;
    Result:=false;
    Exit;
  end;

  GetSVNLine(src, s); // skip empty line
  if (s='') and (status=dsRevision) or (status=dsNode) then begin
    found := dsEof;
    Status := dsEof;
    Result := false;
    Exit;
  end;

  propLen := -1;
  cntLen := -1;
  txtCntLen := -1;
  if Pos('Revision-number', s)=1 then begin
    found:=dsRevision;

    ResetRevInfo;
    repeat
      ConsumeCommand(s);
      GetSVNLine(src, s); // skip empty line
    until s=''; // ends with a mandatory line space

    if (cntLen>=0) and (propLen<0) then propLen := cntLen;

    if (propLen>0) then begin
      propOfs := src.Position;
      SetLength(revProp, propLen);
      src.Read(revProp[1], propLen);
    end;

  end else if Pos('Node-path', s)=1 then begin
    InitNodeInfo(nodeInfo);

    found:=dsNode;
    repeat
      ConsumeCommand(s);
      GetSVNLine(src, s); // skip empty line
    until s=''; // ends with a mandatory line space

    if propLen>0 then begin
      propOfs := src.Position;
      src.Position := src.Position + propLen;
    end else
      propOfs := -1;

    if txtCntLen>0 then begin
      txtCntOfs := src.Position;
      src.Position := src.Position + txtCntLen;
    end else
      txtCntOfs := -1;

    if cntLen>=0 then
      GetSVNLine(src, s); // skip eof

  end else
    found := dsError;

  if (found=dsNode) or (found=dsRevision) then begin
    Result := true;
    GetSVNLine(src, s); // skip eof
  end else
    Result := false;
end;

end.

