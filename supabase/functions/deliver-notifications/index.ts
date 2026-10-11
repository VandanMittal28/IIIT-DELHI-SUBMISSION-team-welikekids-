import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import { importPKCS8, SignJWT } from "npm:jose@6.1.0";

type Job = { job_id:string; device_token:string; notification_title:string; notification_body:string; notification_payload:Record<string,unknown>; attempt_number:number };

Deno.serve(async (request) => {
  const expected = Deno.env.get("DELIVERY_WEBHOOK_SECRET");
  if (!expected || request.headers.get("authorization") !== `Bearer ${expected}`) return new Response("Unauthorized",{status:401});
  const required=["SUPABASE_URL","SUPABASE_SERVICE_ROLE_KEY","APNS_KEY_ID","APNS_TEAM_ID","APNS_BUNDLE_ID","APNS_PRIVATE_KEY"] as const;
  const missing=required.filter(key=>!Deno.env.get(key));
  if(missing.length) return Response.json({error:"NOT_CONFIGURED",missing},{status:503});
  const supabase=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
  const {data,error}=await supabase.rpc("claim_notification_jobs",{p_limit:25});
  if(error) return Response.json({error:error.message},{status:500});
  const key=await importPKCS8(Deno.env.get("APNS_PRIVATE_KEY")!.replace(/\\n/g,"\n"),"ES256");
  const token=await new SignJWT({}).setProtectedHeader({alg:"ES256",kid:Deno.env.get("APNS_KEY_ID")!}).setIssuer(Deno.env.get("APNS_TEAM_ID")!).setIssuedAt().sign(key);
  let delivered=0;
  for(const job of (data??[]) as Job[]){
    const production=Deno.env.get("APNS_ENVIRONMENT")==="production";
    const response=await fetch(`https://${production?"api":"api.sandbox"}.push.apple.com/3/device/${job.device_token}`,{method:"POST",headers:{authorization:`bearer ${token}`,"apns-topic":Deno.env.get("APNS_BUNDLE_ID")!,"apns-push-type":"alert","content-type":"application/json"},body:JSON.stringify({aps:{alert:{title:job.notification_title,body:job.notification_body},sound:"default"},sidequest:job.notification_payload})});
    const errorText=response.ok?null:`${response.status} ${await response.text()}`;
    await supabase.rpc("complete_notification_job",{p_job_id:job.job_id,p_delivered:response.ok,p_error:errorText});
    if(response.ok) delivered++;
  }
  return Response.json({claimed:(data??[]).length,delivered});
});
