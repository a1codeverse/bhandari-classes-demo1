import {NextRequest,NextResponse} from "next/server";
import {requireAdminApi} from "@/lib/auth";
export const runtime="nodejs";
export async function POST(request:NextRequest){
 const a=await requireAdminApi();
 if(!a.ok)return NextResponse.json({error:a.error},{status:a.status});
 const b=await request.json().catch(()=>null);
 const courseId=typeof b?.courseId==="string"?b.courseId:"";
 const title=typeof b?.title==="string"?b.title.trim():"";
 const filePath=typeof b?.filePath==="string"?b.filePath:"";
 const size=Number(b?.sizeBytes);
 const contentType=typeof b?.contentType==="string"?b.contentType:"";
 const expectedPrefix="/bhandari-private-videos/"+courseId+"/";
 if(!courseId||title.length<3||title.length>140||!filePath.startsWith(expectedPrefix)||!Number.isFinite(size)||size<=0||size>4*1024*1024*1024||!["video/mp4","video/webm"].includes(contentType)){
  return NextResponse.json({error:"Invalid course, title or uploaded video details."},{status:400});
 }
 const{data:course}=await a.supabase.from("courses").select("id").eq("id",courseId).maybeSingle();
 if(!course)return NextResponse.json({error:"Course not found."},{status:404});
 const{data,error}=await a.supabase.from("lessons").insert({course_id:courseId,title,object_key:filePath,content_type:contentType,size_bytes:size,is_published:false,created_by:a.user.id}).select("id,title").single();
 if(error)return NextResponse.json({error:error.message},{status:400});
 return NextResponse.json({lesson:data},{status:201});
}