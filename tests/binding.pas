program Binding;
{$mode objfpc}{$H+}
uses cthreads, SysUtils, fpjson, Licensebox;
var C: TLicenseboxClient; V: TJSONData;
begin
 if DeriveBinding('demo','linux-machine-id','12345678123456789abc1234567890ab')<>'m1:linux-machine-id:783b8906a4af61095e68f3f0b4468a953be69ddd7afcf35850b501a7361f309e' then Halt(1);
 C:=TLicenseboxClient.Create('{"product":"demo","keys":{"test-key":"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"},"directory":"build/test-state"}');
 try
  try V:=C.Status; V.Free; Halt(2); except on E: ELicensebox do if E.Code<>'not_signed_in' then raise; end;
  C.Logout; C.Close; C.Close;
  try V:=C.Status; V.Free; Halt(3); except on E: ELicensebox do if E.Code<>'invalid_argument' then raise; end;
 finally C.Free; end;
 WriteLn('binding checks passed');
end.
