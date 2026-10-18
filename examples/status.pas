program StatusExample;
{$mode objfpc}{$H+}{$codepage utf8}
uses cthreads, SysUtils, fpjson, Licensebox;
var C: TLicenseboxClient; V: TJSONData;
begin
 C:=TLicenseboxClient.Create('{"product":"your-product","keys":{"current":"YOUR_PUBLIC_KEY"}}');
 try
  try V:=C.RequireModule('core'); try WriteLn(V.AsJSON); finally V.Free; end;
  except on E: ELicensebox do WriteLn(StdErr,E.Code,': ',E.Message); end;
 finally C.Free; end;
end.
