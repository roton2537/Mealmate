export type Member = { id: string; name: string; nameBn: string }
export const MEMBERS: Member[] = [
 { id:'roton', name:'MD ROTON MIAH', nameBn:'এমডি রোটন মিয়া' },
 { id:'ajib', name:'AJIBUR RAHMAN', nameBn:'আজিবুর রহমান' },
 { id:'robiul', name:'ROBIUL ISLAM', nameBn:'রবিউল ইসলাম' },
 { id:'hindi', name:'HINDI', nameBn:'হিন্দি' },
]
export function splitEqually(amount:number, memberCount=MEMBERS.length):number[] {
 if (!Number.isFinite(amount) || amount<=0) throw new Error('Amount must be greater than zero')
 if (!Number.isInteger(memberCount) || memberCount<1) throw new Error('At least one member is required')
 const halalas=Math.round((amount+Number.EPSILON)*100), base=Math.floor(halalas/memberCount), remainder=halalas%memberCount
 return Array.from({length:memberCount},(_,i)=>(base+(i<remainder?1:0))/100)
}
export function formatSAR(amount:number,locale:'en'|'bn'='en'):string {
 return new Intl.NumberFormat(locale==='bn'?'bn-BD':'en-SA',{style:'currency',currency:'SAR',minimumFractionDigits:2}).format(amount)
}
