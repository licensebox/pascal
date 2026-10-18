program Adapter;
{$mode objfpc}{$H+}{$codepage utf8}
uses cthreads, SysUtils, fpjson, jsonparser, Licensebox;
var R: TJSONObject;
function ClockFn(P: Pointer): Double; cdecl; begin Result:=R.Get('now',0.0); end;
function BindingFn(P: Pointer; Output: PChar; Capacity: SizeUInt): LongInt; cdecl;
var S: string;
begin S:=R.Get('binding',''); if Length(S)>=Capacity then Exit(1); StrPCopy(Output,S); Result:=0; end;
procedure SignInFn(P: Pointer; URL, Code: PChar); cdecl; begin end;
function Run: TJSONData;
var Op, Product: string; C: TLicenseboxClient; O: TJSONObject; CB: TCallbacks;
begin
 Op:=R.Get('op',''); Product:=R.Get('product','');
 if Op='derive' then Exit(TJSONString.Create(DeriveBinding(Product,R.Get('source',''),R.Get('raw_id',''))));
 if Op='native' then Exit(TJSONString.Create(NativeBinding(Product)));
 if Op='verify' then Exit(VerifyLease(R.Get('token',''),Product,R.Objects['keys'].AsJSON,R.Get('now',0.0)));
 O:=TJSONObject.Create; C:=nil;
 try
  O.Add('product',Product); O.Add('keys',R.Objects['keys'].Clone); O.Add('server',R.Get('server','')); O.Add('directory',R.Get('directory','')); O.Add('version','conformance');
  if R.Find('ca_bundle')<>nil then O.Add('ca_bundle',R.Get('ca_bundle',''));
  FillChar(CB,SizeOf(CB),0); CB.Clock:=@ClockFn; CB.OnSignIn:=@SignInFn;
  if R.Find('binding')<>nil then CB.MachineBinding:=@BindingFn;
  C:=TLicenseboxClient.Create(O.AsJSON,CB);
  if Op='require' then Exit(C.RequireModule(R.Get('module','core')));
  if (Op='heartbeat') or (Op='heartbeat-repeat') or (Op='heartbeat-after-require') then begin
   if Op='heartbeat-after-require' then C.RequireModule('core').Free;
   if Op='heartbeat-repeat' then C.Heartbeat(R.Get('module','core')).Free;
   Exit(C.Heartbeat(R.Get('module','core')));
  end;
  if Op='repeat' then begin C.RequireModule('core').Free; Exit(C.RequireModule('core')); end;
  if Op='sign_in' then Exit(C.SignIn(3));
  if Op='request' then Exit(C.RequestAccess(['export'],'café – test'));
  if Op='record' then begin C.RecordUsage('export',True,0.125); C.RecordUsage('export',False,0.025); Exit(TJSONNull.Create); end;
  Result:=C.Call(Op);
 finally C.Free; O.Free; end;
end;
var Input, Line: string; Answer: TJSONObject;
begin
 Input:=''; while not EOF(System.Input) do begin ReadLn(Line); Input:=Input+Line; end;
 R:=TJSONObject(GetJSON(Input)); Answer:=TJSONObject.Create;
 try
  try Answer.Add('value',Run); Answer.Add('ok',True);
  except on E: ELicensebox do begin Answer.Add('ok',False); Answer.Add('error',E.Code); end; end;
  WriteLn(Answer.AsJSON);
 finally Answer.Free; R.Free; end;
end.
