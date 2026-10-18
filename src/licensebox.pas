unit Licensebox;
{$mode objfpc}{$H+}
interface
uses cwstring, SysUtils, SyncObjs, fpjson, jsonparser;
type
  ELicensebox = class(Exception)
    Code: string;
    constructor CreateCode(const ACode, Detail: string);
  end;
  TSignIn = procedure(Context: Pointer; URL, Code: PChar); cdecl;
  TClock = function(Context: Pointer): Double; cdecl;
  TBinding = function(Context: Pointer; Output: PChar; Capacity: SizeUInt): LongInt; cdecl;
  TCancelled = function(Context: Pointer): LongInt; cdecl;
  TCallbacks = record
    Context: Pointer;
    OnSignIn: TSignIn;
    Clock: TClock;
    MachineBinding: TBinding;
    Cancelled: TCancelled;
  end;
  { Instances own their handle. Object references alias safely; never Free twice.
    Callbacks/context are borrowed and must outlive the client. Never raise from
    a cdecl callback. Clock/binding are trusted platform/test seams only. }
  TLicenseboxClient = class
  private
    FHandle: Pointer;
    FLock: TCriticalSection;
    FBusy: Boolean;
    FCallbacks: TCallbacks;
  public
    constructor Create(const OptionsJSON: string); overload;
    constructor Create(const OptionsJSON: string; const Callbacks: TCallbacks); overload;
    destructor Destroy; override;
    procedure Close;
    function Call(const Operation: string; const ArgsJSON: string = '{}'): TJSONData;
    function Lease: TJSONData;
    function RequireModule(const Name: string): TJSONData;
    function Status: TJSONData;
    function SignIn(Timeout: Double = 0): TJSONData;
    procedure Logout;
    function Modules: TJSONData;
    function Requests: TJSONData;
    function RequestAccess(const Names: array of string; const Note: string = ''): TJSONData;
    function AccessLink: string;
    procedure RecordUsage(const Command: string; Success: Boolean; Elapsed: Double);
  end;
function DeriveBinding(const Product, Source, RawID: string): string;
function NativeBinding(const Product: string): string;
function VerifyLease(const Token, Product, KeysJSON: string; Now: Double): TJSONData;
implementation
function lb_client_create_json(Options: PChar; Callbacks: Pointer; out Handle: Pointer): LongInt; cdecl; external 'licensebox';
function lb_client_call_json(Handle: Pointer; Op, Args: PChar; out Output: PChar): LongInt; cdecl; external 'licensebox';
procedure lb_client_destroy(Handle: Pointer); cdecl; external 'licensebox';
procedure lb_free(Output: Pointer); cdecl; external 'licensebox';
function lb_result_code(Code: LongInt): PChar; cdecl; external 'licensebox';
function lb_error_code(Handle: Pointer): PChar; cdecl; external 'licensebox';
function lb_error_message(Handle: Pointer): PChar; cdecl; external 'licensebox';
function lb_derive_binding(Product, Source, RawID, Output: PChar; Capacity: SizeUInt): LongInt; cdecl; external 'licensebox';
function lb_native_binding(Product, Output: PChar; Capacity: SizeUInt): LongInt; cdecl; external 'licensebox';
function lb_verify_lease_json(Token, Product, Keys: PChar; Now: Double; out Output: PChar): LongInt; cdecl; external 'licensebox';
constructor ELicensebox.CreateCode(const ACode, Detail: string);
begin Code := ACode; inherited Create(Detail); end;
procedure Valid(const S: string);
begin if Pos(#0,S)>0 then raise ELicensebox.CreateCode('invalid_argument','NUL in argument'); end;
procedure Check(Code: LongInt; Handle: Pointer = nil);
var C, M: string;
begin
 if Code=0 then Exit;
 C:=string(lb_result_code(Code)); M:=C;
 if (Handle<>nil) and (C<>'invalid_argument') then begin
   if string(lb_error_code(Handle))<>'ok' then C:=string(lb_error_code(Handle));
   M:=string(lb_error_message(Handle));
 end;
 raise ELicensebox.CreateCode(C,M);
end;
function OwnedJSON(P: PChar): TJSONData;
begin
 if P=nil then raise ELicensebox.CreateCode('protocol_error','missing native result');
 try Result:=GetJSON(string(P)); finally lb_free(P); end;
end;
constructor TLicenseboxClient.Create(const OptionsJSON: string);
var C: TCallbacks;
begin FillChar(C,SizeOf(C),0); Create(OptionsJSON,C); end;
constructor TLicenseboxClient.Create(const OptionsJSON: string; const Callbacks: TCallbacks);
begin
 inherited Create; FLock:=TCriticalSection.Create; FHandle:=nil;
 FCallbacks:=Callbacks; Valid(OptionsJSON);
 Check(lb_client_create_json(PChar(OptionsJSON),@FCallbacks,FHandle));
end;
procedure TLicenseboxClient.Close;
begin
 FLock.Acquire;
 try
  if FBusy then raise ELicensebox.CreateCode('invalid_argument','callback reentry');
  if FHandle<>nil then begin lb_client_destroy(FHandle); FHandle:=nil; end;
 finally FLock.Release; end;
end;
destructor TLicenseboxClient.Destroy;
begin if FLock<>nil then begin Close; FLock.Free; end; inherited Destroy; end;
function TLicenseboxClient.Call(const Operation, ArgsJSON: string): TJSONData;
var P: PChar; R: LongInt;
begin
 Valid(Operation); Valid(ArgsJSON); FLock.Acquire;
 try
  if FBusy or (FHandle=nil) then raise ELicensebox.CreateCode('invalid_argument','client closed or callback reentry');
  FBusy:=True; P:=nil;
  try
   R:=lb_client_call_json(FHandle,PChar(Operation),PChar(ArgsJSON),P);
   if R<>0 then begin lb_free(P); Check(R,FHandle); end;
   Result:=OwnedJSON(P);
  finally FBusy:=False; end;
 finally FLock.Release; end;
end;
function TLicenseboxClient.Lease: TJSONData; begin Result:=Call('lease'); end;
function TLicenseboxClient.RequireModule(const Name: string): TJSONData;
var A: TJSONObject;
begin A:=TJSONObject.Create(['module',Name]); try Result:=Call('require',A.AsJSON); finally A.Free; end; end;
function TLicenseboxClient.Status: TJSONData; begin Result:=Call('status'); end;
function TLicenseboxClient.SignIn(Timeout: Double): TJSONData;
var A: TJSONObject;
begin A:=TJSONObject.Create; A.Add('timeout',Timeout); try Result:=Call('sign_in',A.AsJSON); finally A.Free; end; end;
procedure TLicenseboxClient.Logout; begin Call('logout').Free; end;
function TLicenseboxClient.Modules: TJSONData; begin Result:=Call('modules'); end;
function TLicenseboxClient.Requests: TJSONData; begin Result:=Call('requests'); end;
function TLicenseboxClient.RequestAccess(const Names: array of string; const Note: string): TJSONData;
var A: TJSONObject; N: TJSONArray; S: string;
begin N:=TJSONArray.Create; for S in Names do N.Add(S); A:=TJSONObject.Create; A.Add('modules',N); A.Add('note',Note); try Result:=Call('request',A.AsJSON); finally A.Free; end; end;
function TLicenseboxClient.AccessLink: string;
var A: TJSONData;
begin A:=Call('access-link'); try Result:=A.AsString; finally A.Free; end; end;
procedure TLicenseboxClient.RecordUsage(const Command: string; Success: Boolean; Elapsed: Double);
var A: TJSONObject;
begin A:=TJSONObject.Create; A.Add('command',Command); A.Add('success',Success); A.Add('elapsed',Elapsed); try Call('record',A.AsJSON).Free; finally A.Free; end; end;
function DeriveBinding(const Product, Source, RawID: string): string;
var B: array[0..127] of Char; R: string;
begin
 Valid(Product); Valid(Source); R:=RawID;
 while (Length(R)>0) and (R[Length(R)]=#0) do Delete(R,Length(R),1);
 if Pos(#0,R)>0 then raise ELicensebox.CreateCode('identity_unavailable','invalid identifier');
 Check(lb_derive_binding(PChar(Product),PChar(Source),PChar(R),@B[0],SizeOf(B))); Result:=string(PChar(@B[0]));
end;
function NativeBinding(const Product: string): string;
var B: array[0..127] of Char;
begin Valid(Product); Check(lb_native_binding(PChar(Product),@B[0],SizeOf(B))); Result:=string(PChar(@B[0])); end;
function VerifyLease(const Token, Product, KeysJSON: string; Now: Double): TJSONData;
var P: PChar; R: LongInt;
begin Valid(Token); Valid(Product); Valid(KeysJSON); P:=nil; R:=lb_verify_lease_json(PChar(Token),PChar(Product),PChar(KeysJSON),Now,P); if R<>0 then begin lb_free(P); Check(R); end; Result:=OwnedJSON(P); end;
end.
