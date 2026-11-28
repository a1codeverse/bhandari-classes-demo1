import {createHmac} from "node:crypto";
import {NextRequest,NextResponse} from "next/server";
import {getUserContext} from "@/lib/auth";
export const runtime="nodejs";
export async function GET(_request:NextRequest,{params}:{params:Promise<{lessonId:string}>}){
 const{lessonId}=await params;
 const c=await getUserContext();
 if(!c)return NextResponse.json({error:"Please sign in."},{status:401});
 const{data:lesson}=await c.supabase.from("lessons").select("id,course_id,object_key,is_published").eq("id",lessonId).maybeSingle();
 if(!lesson)return NextResponse.json({error:"Lesson not found."},{status:404});
 if(c.profile.role!=="admin"){
  if(!lesson.is_published)return NextResponse.json({error:"Lesson is not published."},{status:404});
  const{data:enrolment}=await c.supabase.from("enrollments").select("id,expires_at,status").eq("user_id",c.user.id).eq("course_id",lesson.course_id).eq("status","active").maybeSingle();
  if(!enrolment||(enrolment.expires_at&&new Date(enrolment.expires_at)<new Date()))return NextResponse.json({error:"An active course enrolment is required."},{status:403});
 }
 const endpoint=process.env.IMAGEKIT_URL_ENDPOINT?.replace(/\/+$/,"");
 const privateKey=process.env.IMAGEKIT_PRIVATE_KEY;
 if(!endpoint||!privateKey)return NextResponse.json({error:"ImageKit delivery is not configured."},{status:503});
 const path=lesson.object_key.replace(/^\/+/,"");
 if(!path.startsWith("bhandari-private-videos/"+lesson.course_id+"/"))return NextResponse.json({error:"Invalid lesson media path."},{status:500});
 const expires=Math.floor(Date.now()/1000)+10*60;
 const signature=createHmac("sha1",privateKey).update(path+expires).digest("hex");
 const url=endpoint+"/"+path+"?ik-t="+expires+"&ik-s="+signature;
 return NextResponse.json({url,expiresIn:600},{headers:{"Cache-Control":"no-store, private"}});
}