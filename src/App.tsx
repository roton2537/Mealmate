import {useEffect,useMemo,useState,type FormEvent} from 'react'
import type {Session} from '@supabase/supabase-js'
import {formatSAR,splitEqually} from './lib/split'
import {messages,type Language} from './i18n'
import {supabase} from './lib/supabase'

type Member={id:string;name:string;name_bn:string;household_id:string;joined_at:string;deactivated_at:string|null}
type Expense={id:string;description:string;amount:number;paid_by_member_id:string;expense_date:string}

function localDateValue(){
 const now=new Date()
 return `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`
}

export default function App(){
 const [lang,setLang]=useState<Language>('en')
 const [session,setSession]=useState<Session|null>(null)
 const [accessCode,setAccessCode]=useState('')
 const [selectedMember,setSelectedMember]=useState('')
 const [memberOptions,setMemberOptions]=useState<{id:string;name:string;name_bn:string}[]>([])
 const [currentMemberId,setCurrentMemberId]=useState('')
 const [newMemberName,setNewMemberName]=useState('')
 const [accessUnlocked,setAccessUnlocked]=useState(()=>localStorage.getItem('mealmate_access_v1')==='yes')
 const [notice,setNotice]=useState('')
 const [error,setError]=useState('')
 const [loading,setLoading]=useState(true)
 const [busy,setBusy]=useState(false)
 const [members,setMembers]=useState<Member[]>([])
 const [householdId,setHouseholdId]=useState('')
 const [expenses,setExpenses]=useState<Expense[]>([])
 const [title,setTitle]=useState('')
 const [amount,setAmount]=useState('')
 const [paidBy,setPaidBy]=useState('')
 const [date,setDate]=useState(localDateValue())
 const [editingId,setEditingId]=useState<string|null>(null)
 const t=messages[lang]

 useEffect(()=>{
  let active=true
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,nextSession)=>{
   if(active)setSession(nextSession)
  })
  void (async()=>{
   const {data,error:sessionError}=await supabase.auth.getSession()
   if(!active)return
   if(sessionError)setError(sessionError.message)
   if(data.session?.user.is_anonymous){setSession(data.session);setLoading(false);return}
   if(data.session)await supabase.auth.signOut()
   const {data:anonymous,error:anonymousError}=await supabase.auth.signInAnonymously()
   if(!active)return
   if(anonymousError){setError('Unable to start a private household session. Anonymous access must be enabled for MealMate.');setLoading(false);return}
   setSession(anonymous.session);setLoading(false)
  })()
  return ()=>{active=false;subscription.unsubscribe()}
 },[])

 const userId=session?.user.id
 useEffect(()=>{
  let active=true
  async function load(){
   if(!userId||!accessUnlocked){setMembers([]);setExpenses([]);setHouseholdId('');setLoading(false);return}
   setLoading(true);setError('')
   const {data:context,error:contextError}=await supabase.rpc('get_mealmate_session_context')
   if(!active)return
   if(contextError){setError(contextError.message);setLoading(false);return}
   const current=context?.[0]
   if(!current){setMembers([]);setExpenses([]);setHouseholdId('');setLoading(false);return}
   const {data:group,error:groupError}=await supabase.from('members').select('id,name,name_bn,household_id,joined_at,deactivated_at').eq('household_id',current.household_id).order('name')
   if(!active)return
   if(groupError){setError(groupError.message);setLoading(false);return}
   const {data:records,error:expenseError}=await supabase.from('expenses').select('id,description,amount,paid_by_member_id,expense_date').eq('household_id',current.household_id).order('expense_date',{ascending:false}).order('created_at',{ascending:false})
   if(!active)return
   if(expenseError){setError(expenseError.message);setLoading(false);return}
   setHouseholdId(current.household_id);setCurrentMemberId(current.member_id);setMembers(group??[]);setExpenses((records??[]) as Expense[])
   setPaidBy(current=>(group??[]).some(m=>m.id===current && !m.deactivated_at)?current:(group??[]).find(m=>!m.deactivated_at)?.id??'')
   setLoading(false)
  }
  void load()
  return ()=>{active=false}
 },[userId,accessUnlocked])

 async function refreshExpenses(){
  const {data,error:loadError}=await supabase.from('expenses').select('id,description,amount,paid_by_member_id,expense_date').eq('household_id',householdId).order('expense_date',{ascending:false}).order('created_at',{ascending:false})
  if(loadError)throw loadError
  setExpenses((data??[]) as Expense[])
 }

 async function unlockHousehold(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setNotice('')
  try{
   if(memberOptions.length===0){
    const {data:list,error:listError}=await supabase.rpc('list_mealmate_members',{p_access_code:accessCode.trim()})
    if(listError)throw listError
    setMemberOptions(list??[])
    setSelectedMember(list?.[0]?.name??'')
    setNotice(lang==='bn'?'কোড সঠিক। এখন আপনার নাম নির্বাচন করুন।':'Code verified. Now choose your name and submit again.')
    return
   }
   const {error:unlockError}=await supabase.rpc('unlock_mealmate_household',{p_access_code:accessCode.trim(),p_member_name:selectedMember})
   if(unlockError)throw unlockError
   localStorage.setItem('mealmate_access_v1','yes')
   setAccessUnlocked(true);setAccessCode('')
   setNotice(lang==='bn'?'পরিবারের অ্যাক্সেস সক্রিয় হয়েছে।':'Household access unlocked on this device.')
  }catch(err){
   setError(err instanceof Error?err.message:'Access code is incorrect or the private session is unavailable.')
  }finally{setBusy(false)}
 }

 function startEdit(item:Expense){
  setEditingId(item.id);setTitle(item.description);setAmount(String(item.amount));setPaidBy(item.paid_by_member_id);setDate(item.expense_date);setError('')
  document.getElementById('expense-form')?.scrollIntoView({behavior:'smooth',block:'center'})
 }

 function cancelEdit(){
  setEditingId(null);setTitle('');setAmount('');setPaidBy(members[0]?.id??'');setDate(localDateValue());setError('')
 }

 async function saveExpense(e:FormEvent<HTMLFormElement>){
  e.preventDefault()
  if(!session||!householdId)return
  const value=Number(amount)
  if(!title.trim()||!Number.isFinite(value)||value<=0){setError(lang==='bn'?'বিবরণ ও সঠিক পরিমাণ দিন।':'Enter a description and a valid amount.');return}
  if(!paidBy||!members.some(member=>member.id===paidBy)){setError(lang==='bn'?'যিনি পরিশোধ করেছেন তাকে নির্বাচন করুন।':'Select a valid payer.');return}
  setBusy(true);setError('')
  try{
   const payload={description:title.trim(),amount:Math.round(value*100)/100,paid_by_member_id:paidBy,expense_date:date}
   const result=editingId
    ? await supabase.from('expenses').update(payload).eq('id',editingId).eq('household_id',householdId)
    : await supabase.from('expenses').insert({...payload,household_id:householdId,created_by:session.user.id})
   if(result.error)throw result.error
   await refreshExpenses()
   cancelEdit()
   setNotice(lang==='bn'?(editingId?'খরচ আপডেট হয়েছে।':'খরচ সংরক্ষণ হয়েছে।'):(editingId?'Expense updated.':'Expense saved.'))
  }catch(err){
   setError(err instanceof Error?err.message:'Unable to save this expense.')
  }finally{setBusy(false)}
 }

 async function deleteExpense(item:Expense){
  const prompt=lang==='bn'?'এই খরচটি স্থায়ীভাবে মুছে ফেলবেন?':'Delete this expense permanently?'
  if(!window.confirm(prompt))return
  setBusy(true);setError('');setNotice('')
  try{
   const {error:deleteError}=await supabase.from('expenses').delete().eq('id',item.id).eq('household_id',householdId)
   if(deleteError)throw deleteError
   if(editingId===item.id)cancelEdit()
   await refreshExpenses()
   setNotice(lang==='bn'?'খরচ মুছে ফেলা হয়েছে।':'Expense deleted.')
  }catch(err){
   setError(err instanceof Error?err.message:'Unable to delete this expense.')
  }finally{setBusy(false)}
 }

 const total=expenses.reduce((sum,item)=>sum+Number(item.amount),0)
 const activeMembers=members.filter(member=>!member.deactivated_at)
 const isAdmin=members.some(member=>member.id===currentMemberId && member.name==='MD ROTON MIAH' && !member.deactivated_at)
 const balances=useMemo(()=>members.map(member=>{
  const paid=expenses.filter(item=>item.paid_by_member_id===member.id).reduce((sum,item)=>sum+Number(item.amount),0)
  const owed=expenses.reduce((sum,item)=>{
   const participants=members.filter(m=>m.joined_at<=item.expense_date && (!m.deactivated_at || m.deactivated_at>=item.expense_date))
   return sum+(participants.some(m=>m.id===member.id)?Number(item.amount)/Math.max(participants.length,1):0)
  },0)
  return {...member,paid,balance:paid-owed}
 }),[members,expenses])
 async function refreshMembers(){
  const {data,error:loadError}=await supabase.from('members').select('id,name,name_bn,household_id,joined_at,deactivated_at').eq('household_id',householdId).order('name')
  if(loadError)throw loadError
  setMembers(data??[])
 }
 async function addMember(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setNotice('')
  try{
   const {error:addError}=await supabase.rpc('add_mealmate_member',{p_name:newMemberName.trim(),p_name_bn:newMemberName.trim()})
   if(addError)throw addError
   await refreshMembers();setNewMemberName('')
   setNotice(lang==='bn'?'নতুন সদস্য যোগ হয়েছে।':'New member added. They can now unlock using the household code.')
  }catch(err){setError(err instanceof Error?err.message:'Unable to add member.')}
  finally{setBusy(false)}
 }
 async function deactivateMember(member:Member){
  if(!window.confirm(lang==='bn'?member.name_bn+' সদস্যকে নিষ্ক্রিয় করবেন?': 'Deactivate '+member.name+'? Their old expenses will remain.'))return
  setBusy(true);setError('');setNotice('')
  try{
   const {error:deactivateError}=await supabase.rpc('deactivate_mealmate_member',{p_member_id:member.id})
   if(deactivateError)throw deactivateError
   await refreshMembers()
   setNotice(lang==='bn'?'সদস্য নিষ্ক্রিয় হয়েছে; পুরোনো হিসাব সংরক্ষিত।':'Member deactivated. Historical expenses are preserved.')
  }catch(err){setError(err instanceof Error?err.message:'Unable to deactivate member.')}
  finally{setBusy(false)}
 }

 return <main className="shell" dir={lang==='bn'?'rtl':'ltr'}>
  <header className="topbar"><a className="brand" href="#top"><span className="brand-mark">M</span><span><strong>{t.app}</strong><small>{t.subtitle}</small></span></a><div className="top-actions"><span className="currency">SAR · ﷼</span><button className="lang-btn" onClick={()=>setLang(lang==='en'?'bn':'en')}>{t.language}</button>{accessUnlocked&&<button className="lang-btn" onClick={()=>{localStorage.removeItem('mealmate_access_v1');setAccessUnlocked(false);setNotice('')}}>{lang==='bn'?'সদস্য বদলান':'Switch member'}</button>}</div></header>
  <section className="welcome" id="top"><div><p className="eyebrow">SHARED HOUSEHOLD FINANCES</p><h1>{lang==='bn'?'খাবারের খরচ, সবার জন্য পরিষ্কার হিসাব।':'A simpler way to share meal costs.'}</h1><p>{lang==='bn'?'চারজন সদস্যের সমান ভাগে দৈনন্দিন খরচের হিসাব রাখুন।':'Track shared food expenses and split costs equally among active members for each expense date.'}</p></div><div className="welcome-icon">🥘</div></section>
  {loading?<section className="panel"><p>{lang==='bn'?'নিরাপদ সেশন চালু হচ্ছে…':'Opening your private household session…'}</p></section>:!accessUnlocked?<section className="panel auth-panel"><div className="panel-heading"><div><p className="eyebrow">PRIVATE HOUSEHOLD ACCESS</p><h2>{lang==='bn'?'পরিবারের অ্যাক্সেস খুলুন':'Unlock your household'}</h2></div><span className="plus">🔒</span></div><p>{lang==='bn'?'শেয়ার করা গোপন অ্যাক্সেস কোড দিন, তারপর সদস্য তালিকা থেকে আপনার নাম নির্বাচন করুন।':'Enter the private household access code and choose your member name. This device will remember your access.'}</p><form onSubmit={unlockHousehold}>{memberOptions.length>0&&<label>{lang==='bn'?'আপনার সদস্য পরিচয়':'Your member name'}<select value={selectedMember} onChange={e=>setSelectedMember(e.target.value)}>{memberOptions.map(member=><option key={member.id} value={member.name}>{lang==='bn'?member.name_bn:member.name}</option>)}</select></label>}<label>{lang==='bn'?'পরিবারের অ্যাক্সেস কোড':'Household access code'}<input value={accessCode} onChange={e=>setAccessCode(e.target.value)} placeholder="Enter your private code" autoComplete="off" required/></label><button className="primary-btn" type="submit" disabled={busy||!accessCode.trim()||(memberOptions.length>0&&!selectedMember)}>{busy?(lang==='bn'?'যাচাই হচ্ছে…':'Verifying…'):(lang==='bn'?'অ্যাক্সেস খুলুন':'Unlock access')}<span>→</span></button></form>{notice&&<p className="balance-note" role="status">{notice}</p>}{error&&<p className="error" role="alert">{error}</p>}</section>:members.length===0?<section className="panel auth-panel"><p className="eyebrow">HOUSEHOLD ACCESS</p><h2>{lang==='bn'?'এই ডিভাইসের অ্যাক্সেস পুনরায় খুলুন':'Reconnect this device'}</h2><p>{lang==='bn'?'এই ডিভাইসের নিরাপদ সেশন নতুন করে তৈরি হয়েছে। আবার পরিবারের কোড দিয়ে প্রবেশ করুন।':'This browser session has changed. Unlock again with the household code to restore access.'}</p><button className="secondary-btn" type="button" onClick={()=>{localStorage.removeItem('mealmate_access_v1');setAccessUnlocked(false)}}>{lang==='bn'?'আবার অ্যাক্সেস খুলুন':'Unlock again'}</button>{error&&<p className="error">{error}</p>}</section>:<>
   <div className="notice"><span className="notice-dot" style={{background:'#3c9a61'}}/>{lang==='bn'?'Supabase সংযুক্ত — পরিবর্তন সব সদস্যের জন্য সংরক্ষিত হবে।':'Connected to Supabase — saved expenses are shared with authorized members.'}</div>
   <section className="stats"><article className="stat-card"><span>{t.total}</span><strong>{formatSAR(total,lang)}</strong><small>{expenses.length} {lang==='bn'?'টি এন্ট্রি':'entries'}</small></article><article className="stat-card"><span>{lang==='bn'?'সক্রিয় সদস্য':'Active members'}</span><strong>{activeMembers.length}</strong><small>{lang==='bn'?'প্রতি খরচে যোগদানের তারিখ অনুযায়ী ভাগ':'Shares depend on each expense date'}</small></article><article className="stat-card"><span>{t.count}</span><strong>{expenses.length}</strong><small>{lang==='bn'?'সব সদস্যের হিসাব':'Across all members'}</small></article></section>
   <section className="content-grid"><article className="panel" id="expense-form"><div className="panel-heading"><div><p className="eyebrow">{editingId?'EDIT RECORD':'NEW RECORD'}</p><h2>{editingId?t.editExpense:t.add}</h2></div><span className="plus">{editingId?'✎':'＋'}</span></div><form onSubmit={saveExpense}><label>{t.description}<input value={title} onChange={e=>setTitle(e.target.value)} placeholder={lang==='bn'?'যেমন: বাজার, চাল, সবজি':'e.g. Groceries, rice, vegetables'} maxLength={160} required/></label><label>{t.amount}<div className="amount-wrap"><span>﷼</span><input type="number" inputMode="decimal" min="0.01" max="10000000" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)} placeholder="0.00" required/></div></label><div className="form-row"><label>{t.paidBy}<select value={paidBy} onChange={e=>setPaidBy(e.target.value)} required>{activeMembers.map(member=><option key={member.id} value={member.id}>{lang==='bn'?member.name_bn:member.name}</option>)}</select></label><label>{t.date}<input type="date" value={date} onChange={e=>setDate(e.target.value)} required/></label></div>{error&&<p className="error" role="alert">{error}</p>}<button className="primary-btn" type="submit" disabled={busy||!paidBy}>{busy?(lang==='bn'?'সংরক্ষণ হচ্ছে…':'Saving…'):(editingId?t.updateExpense:t.save)}<span>{editingId?'✓':'＋'}</span></button>{editingId&&<button className="secondary-btn" type="button" onClick={cancelEdit} disabled={busy}>{t.cancel}</button>}</form></article>
   <article className="panel"><div className="panel-heading"><div><p className="eyebrow">THE GROUP</p><h2>{t.members}</h2></div><span className="member-count">{String(members.length).padStart(2,'0')}</span></div><div className="member-list">{balances.map((member,index)=><div className="member-row" key={member.id}><span className={'avatar avatar-'+(index%4)}>{member.name.slice(0,1)}</span><span className="member-name"><strong>{lang==='bn'?member.name_bn:member.name}{member.deactivated_at?' · '+(lang==='bn'?'নিষ্ক্রিয়':'Inactive'):''}</strong><small>{t.paid}: {formatSAR(member.paid,lang)}</small></span><span className={member.balance>=0?'positive':'negative'}>{member.balance>=0?'+':'−'}{formatSAR(Math.abs(member.balance),lang)}</span></div>)}</div><p className="balance-note">{lang==='bn'?'ইতিবাচক = তারিখভিত্তিক অংশের চেয়ে বেশি পরিশোধ করেছেন।':'Positive means paid more than their date-based share. New members join expenses from their joining date.'}</p>
   {isAdmin&&<div className="member-admin"><h3>{lang==='bn'?'সদস্য পরিচালনা':'Manage members'} ({activeMembers.length}/6)</h3><form onSubmit={addMember}><label>{lang==='bn'?'নতুন সদস্যের নাম':'New member name'}<input value={newMemberName} onChange={e=>setNewMemberName(e.target.value)} maxLength={80} minLength={2} placeholder="Full name" required disabled={activeMembers.length>=6}/></label><button className="secondary-btn" type="submit" disabled={busy||activeMembers.length>=6||!newMemberName.trim()}>{lang==='bn'?'সদস্য যোগ করুন':'Add member'}</button></form>{members.filter(m=>!m.deactivated_at&&m.id!==currentMemberId).map(m=><div className="member-row" key={m.id}><span className="member-name"><strong>{m.name}</strong><small>{lang==='bn'?'যোগদানের তারিখ':'Joined'}: {m.joined_at}</small></span><button className="text-action danger-action" type="button" onClick={()=>void deactivateMember(m)} disabled={busy||activeMembers.length<=3}>{lang==='bn'?'নিষ্ক্রিয়':'Deactivate'}</button></div>)}</div>}
   </article></section>
   <section className="panel recent-panel"><div className="panel-heading"><div><p className="eyebrow">ACTIVITY</p><h2>{t.recent}</h2></div><span className="activity-count">{expenses.length}</span></div>{expenses.length===0?<div className="empty"><span>🧾</span><p>{t.noExpenses}</p></div>:<div className="expense-list">{expenses.map(item=>{const member=members.find(m=>m.id===item.paid_by_member_id);return <div className="expense-row" key={item.id}><span className="expense-icon">🛒</span><span className="expense-info"><strong>{item.description}</strong><small>{member?(lang==='bn'?member.name_bn:member.name):'—'} · {item.expense_date}</small></span><strong className="expense-amount">{formatSAR(Number(item.amount),lang)}</strong><span className="expense-actions"><button type="button" className="text-action" onClick={()=>startEdit(item)} disabled={busy} aria-label={t.editExpense}>{t.edit}</button><button type="button" className="text-action danger-action" onClick={()=>void deleteExpense(item)} disabled={busy} aria-label={t.delete}>{t.delete}</button></span></div>})}</div>}</section>
   {notice&&<p className="balance-note" role="status">{notice}</p>}
  </>}
  {error&&accessUnlocked&&members.length>0&&<p className="error" role="alert">{error}</p>}
  <footer>MealMate <span>·</span> {lang==='bn'?'সমান ভাগ, সহজ হিসাব':'Fair shares. Clear records.'}</footer>
 </main>
}
