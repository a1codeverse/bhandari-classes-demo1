import {createHmac,randomUUID} from "node:crypto";
import {NextRequest,NextResponse} from "next/server";
import {requireAdminApi} from "@/lib/auth";
export const runtime="nodejs";
const MAX_FILE_BYTES=4*1024*1024*1024;
export async function POST(request:NextRequest){
 const a=await requireAdminApi();
 if(!a.ok)return NextResponse.json({error:a.error},{status:a.status});
 const b=await request.json().catch(()=>null);
 const courseId=typeof b?.courseId==="string"?b.courseId:"";
 const fileName=typeof b?.fileName==="string"?b.fileName:"";
 const contentType=typeof b?.contentType==="string"?b.contentType:"";
 const size=Number(b?.sizeBytes);
 if(!courseId||!fileName||!Number.isFinite(size)||size<=0||size>MAX_FILE_BYTES)return NextResponse.json({error:"Invalid file or file exceeds the 4GB upload limit."},{status:400});
 if(!["video/mp4","video/webm"].includes(contentType))return NextResponse.json({error:"Only MP4 and WebM files are accepted."},{status:415});
 const{data:course}=await a.supabase.from("courses").select("id").eq("id",courseId).maybeSingle();
 if(!course)return NextResponse.json({error:"Course not found."},{status:404});
 const privateKey=process.env.IMAGEKIT_PRIVATE_KEY;
 const publicKey=process.env.IMAGEKIT_PUBLIC_KEY;
 if(!privateKey||!publicKey)return NextResponse.json({error:"ImageKit server credentials are not configured."},{status:503});
 const token=randomUUID();
 const expire=Math.floor(Date.now()/1000)+30*60;
 const signature=createHmac("sha1",privateKey).update(token+expire).digest("hex");
 const folder="/bhandari-private-videos/"+courseId;
 return NextResponse.json({token,expire,signature,publicKey,folder},{headers:{"Cache-Control":"no-store, private"}});
}