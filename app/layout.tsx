import type {Metadata} from "next";import "./globals.css";
export const metadata:Metadata={title:"Bhandari Classes | Mathematics & Quantitative Aptitude",description:"Concept-first mathematics for Classes 8–12 and quantitative aptitude preparation."};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>;}