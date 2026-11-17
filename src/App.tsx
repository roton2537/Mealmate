import {useEffect,useMemo,useState,type FormEvent} from 'react'
import type {Session} from '@supabase/supabase-js'
import {formatSAR,splitEqually} from './lib/split'
import {messages,type Language} from './i18n'
import {supabase} from './lib/supabase'

type Member={id:string;name:string;name_bn:string;household_id:string}
type Expense={id:string;description:string;amount:number;paid_by_member_id:string;expense_date:string}

function localDateValue(){
 const now=new Date()
 return `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`
}

export default function App(){
 const [lang,setLang]=useState<Language>('en')
 const [session,setSession]=useState<Session|null>(null)
 const [email,setEmail]=useState('')
 const [password,setPassword]=useState('')
 const [newPassword,setNewPassword]=useState('')
 const [passwordNotice,setPasswordNotice]=useState('')
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
  void supabase.auth.getSession().then(({data,error:sessionError})=>{
   if(!active)return
   if(sessionError)setError(sessionError.message)
   setSession(data.session)
   if(!data.session)setLoading(false)
  })
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,nextSession)=>{
   if(active)setSession(nextSession)
  })
  return ()=>{active=false;subscription.unsubscribe()}
 },[])

 const userId=session?.user.id
 useEffect(()=>{
  let active=true
  async function load(){
   if(!userId){setMembers([]);setExpenses([]);setHouseholdId('');setLoading(false);return}
   setLoading(true);setError('')
   const {data:mine,error:memberError}=await supabase.from('members').select('id,name,name_bn,household_id').eq('auth_user_id',userId).maybeSingle()
   if(!active)return
   if(memberError){setError(memberError.message);setLoading(false);return}
   if(!mine){setMembers([]);setExpenses([]);setHouseholdId('');setLoading(false);return}
   const {data:group,error:groupError}=await supabase.from('members').select('id,name,name_bn,household_id').eq('household_id',mine.household_id).order('name')
   if(!active)return
   if(groupError){setError(groupError.message);setLoading(false);return}
   const {data:records,error:expenseError}=await supabase.from('expenses').select('id,description,amount,paid_by_member_id,expense_date').eq('household_id',mine.household_id).order('expense_date',{ascending:false}).order('created_at',{ascending:false})
   if(!active)return
   if(expenseError){setError(expenseError.message);setLoading(false);return}
   setHouseholdId(mine.household_id);setMembers(group??[]);setExpenses((records??[]) as Expense[])
   setPaidBy(current=>(group??[]).some(m=>m.id===current)?current:(group??[])[0]?.id??'')
   setLoading(false)
  }
  void load()
  return ()=>{active=false}
 },[userId])

 async function refreshExpenses(){
  const {data,error:loadError}=await supabase.from('expenses').select('id,description,amount,paid_by_member_id,expense_date').eq('household_id',householdId).order('expense_date',{ascending:false}).order('created_at',{ascending:false})
  if(loadError)throw loadError
  setExpenses((data??[]) as Expense[])
 }

 async function signIn(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setNotice('')
  try{
   const {error:authError}=await supabase.auth.signInWithPassword({email:email.trim(),password})
   if(authError)setError(lang==='bn'?'ইমেইল বা পাসওয়ার্ড সঠিক নয়, অথবা অ্যাকাউন্টটি সক্রিয় নয়।':'Email or password is incorrect, or this account is not active.')
  }catch(err){
   setError(err instanceof Error?err.message:'Unable to sign in.')
  }finally{setBusy(false)}
 }

 async function updatePassword(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setPasswordNotice('')
  if(newPassword.length<8){setError(lang==='bn'?'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।':'Use a password with at least 8 characters.');setBusy(false);return}
  try{
   const {error:passwordError}=await supabase.auth.updateUser({password:newPassword})
   if(passwordError)throw passwordError
   setNewPassword('');setPasswordNotice(lang==='bn'?'পাসওয়ার্ড সফলভাবে আপডেট হয়েছে।':'Password updated successfully.')
  }catch(err){setError(err instanceof Error?err.message:'Unable to update password.')}
  finally{setBusy(false)}
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

 async function signOut(){
  await supabase.auth.signOut();setNotice('');setError('');cancelEdit()
 }

 const total=expenses.reduce((sum,item)=>sum+Number(item.amount),0)
 const share=total/Math.max(members.length,1)
 const balances=useMemo(()=>members.map((member,index)=>{
  const paid=expenses.filter(item=>item.paid_by_member_id===member.id).reduce((sum,item)=>sum+Number(item.amount),0)
  const owed=expenses.reduce((sum,item)=>sum+splitEqually(Number(item.amount),Math.max(members.length,1))[index],0)
  return {...member,paid,balance:paid-owed}
 }),[members,expenses])

 return <main className="shell" dir={lang==='bn'?'rtl':'ltr'}>
  <header className="topbar"><a className="brand" href="#top"><span className="brand-mark">M</span><span><strong>{t.app}</strong><small>{t.subtitle}</small></span></a><div className="top-actions"><span className="currency">SAR · ﷼</span><button className="lang-btn" onClick={()=>setLang(lang==='en'?'bn':'en')}>{t.language}</button>{session&&<button className="lang-btn" onClick={()=>void signOut()}>{lang==='bn'?'লগআউট':'Sign out'}</button>}</div></header>
  <section className="welcome" id="top"><div><p className="eyebrow">SHARED HOUSEHOLD FINANCES</p><h1>{lang==='bn'?'খাবারের খরচ, সবার জন্য পরিষ্কার হিসাব।':'A simpler way to share meal costs.'}</h1><p>{lang==='bn'?'চারজন সদস্যের সমান ভাগে দৈনন্দিন খরচের হিসাব রাখুন।':'Track shared food expenses and split every cost equally between the four members.'}</p></div><div className="welcome-icon">🥘</div></section>
  {!session?<section className="panel auth-panel"><div className="panel-heading"><div><p className="eyebrow">SECURE MEMBER ACCESS</p><h2>{lang==='bn'?'ইমেইল দিয়ে প্রবেশ করুন':'Member sign in'}</h2></div><span className="plus">↗</span></div><p>{lang==='bn'?'অনুমোদিত সদস্যের নিবন্ধিত ইমেইল ও পাসওয়ার্ড ব্যবহার করুন।':'Use the email and password provided for your approved member account. Only pre-approved member accounts can sign in.'}</p><form onSubmit={signIn}><label>{lang==='bn'?'ইমেইল ঠিকানা':'Email address'}<input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@example.com" required autoComplete="username"/></label><label>{lang==='bn'?'পাসওয়ার্ড':'Password'}<input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder={lang==='bn'?'আপনার পাসওয়ার্ড':'Your password'} required autoComplete="current-password" minLength={8}/></label><button className="primary-btn" type="submit" disabled={busy}>{busy?(lang==='bn'?'প্রবেশ করা হচ্ছে…':'Signing in…'):(lang==='bn'?'লগইন করুন':'Sign in')}<span>→</span></button></form>{notice&&<p className="balance-note" role="status">{notice}</p>}{error&&<p className="error" role="alert">{error}</p>}</section>:loading?<section className="panel"><p>{lang==='bn'?'তথ্য লোড হচ্ছে…':'Loading your shared household…'}</p></section>:members.length===0?<section className="panel auth-panel"><p className="eyebrow">MEMBER ACCESS NOT YET LINKED</p><h2>{lang==='bn'?'অ্যাক্সেস এখনো সক্রিয় নয়':'Your account is not linked yet'}</h2><p>{lang==='bn'?'এই ইমেইলটি MealMate সদস্যের সাথে যুক্ত করা হয়নি। প্রশাসক সদস্যের পরিচয় যাচাই করে সংযুক্ত করলে আপনি প্রবেশ করতে পারবেন।':'This signed-in account is not linked to one of the four approved members yet. An administrator must verify and link your account before shared data becomes visible.'}</p>{error&&<p className="error">{error}</p>}<button className="lang-btn" onClick={()=>void signOut()}>{lang==='bn'?'লগআউট':'Sign out'}</button></section>:<>
   <div className="notice"><span className="notice-dot" style={{background:'#3c9a61'}}/>{lang==='bn'?'Supabase সংযুক্ত — পরিবর্তন সব সদস্যের জন্য সংরক্ষিত হবে।':'Connected to Supabase — saved expenses are shared with authorized members.'}</div>
   <section className="panel auth-panel"><div className="panel-heading"><div><p className="eyebrow">ACCOUNT SECURITY</p><h2>{lang==='bn'?'পাসওয়ার্ড সেট বা পরিবর্তন':'Set or change your password'}</h2></div></div><form onSubmit={updatePassword}><label>{lang==='bn'?'নতুন পাসওয়ার্ড (কমপক্ষে ৮ অক্ষর)':'New password (at least 8 characters)'}<input type="password" value={newPassword} onChange={e=>setNewPassword(e.target.value)} minLength={8} autoComplete="new-password" required/></label><button className="secondary-btn" type="submit" disabled={busy}>{lang==='bn'?'পাসওয়ার্ড সংরক্ষণ':'Save password'}</button></form>{passwordNotice&&<p className="balance-note" role="status">{passwordNotice}</p>}<p className="balance-note">{lang==='bn'?'পাসওয়ার্ড ভুলে গেলে প্রশাসকের সহায়তা লাগবে; ইমেইল রিসেট এখনো কনফিগার করা হয়নি।':'If you forget your password, an administrator will need to help; email-based password recovery is not configured yet.'}</p></section>
   <section className="stats"><article className="stat-card"><span>{t.total}</span><strong>{formatSAR(total,lang)}</strong><small>{expenses.length} {lang==='bn'?'টি এন্ট্রি':'entries'}</small></article><article className="stat-card"><span>{t.perPerson}</span><strong>{formatSAR(share,lang)}</strong><small>{t.equal}</small></article><article className="stat-card"><span>{t.count}</span><strong>{expenses.length}</strong><small>{lang==='bn'?'সব সদস্যের হিসাব':'Across all members'}</small></article></section>
   <section className="content-grid"><article className="panel" id="expense-form"><div className="panel-heading"><div><p className="eyebrow">{editingId?'EDIT RECORD':'NEW RECORD'}</p><h2>{editingId?t.editExpense:t.add}</h2></div><span className="plus">{editingId?'✎':'＋'}</span></div><form onSubmit={saveExpense}><label>{t.description}<input value={title} onChange={e=>setTitle(e.target.value)} placeholder={lang==='bn'?'যেমন: বাজার, চাল, সবজি':'e.g. Groceries, rice, vegetables'} maxLength={160} required/></label><label>{t.amount}<div className="amount-wrap"><span>﷼</span><input type="number" inputMode="decimal" min="0.01" max="10000000" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)} placeholder="0.00" required/></div></label><div className="form-row"><label>{t.paidBy}<select value={paidBy} onChange={e=>setPaidBy(e.target.value)} required>{members.map(member=><option key={member.id} value={member.id}>{lang==='bn'?member.name_bn:member.name}</option>)}</select></label><label>{t.date}<input type="date" value={date} onChange={e=>setDate(e.target.value)} required/></label></div>{error&&<p className="error" role="alert">{error}</p>}<button className="primary-btn" type="submit" disabled={busy||!paidBy}>{busy?(lang==='bn'?'সংরক্ষণ হচ্ছে…':'Saving…'):(editingId?t.updateExpense:t.save)}<span>{editingId?'✓':'＋'}</span></button>{editingId&&<button className="secondary-btn" type="button" onClick={cancelEdit} disabled={busy}>{t.cancel}</button>}</form></article>
   <article className="panel"><div className="panel-heading"><div><p className="eyebrow">THE GROUP</p><h2>{t.members}</h2></div><span className="member-count">{String(members.length).padStart(2,'0')}</span></div><div className="member-list">{balances.map((member,index)=><div className="member-row" key={member.id}><span className={'avatar avatar-'+index}>{member.name.slice(0,1)}</span><span className="member-name"><strong>{lang==='bn'?member.name_bn:member.name}</strong><small>{t.paid}: {formatSAR(member.paid,lang)}</small></span><span className={member.balance>=0?'positive':'negative'}>{member.balance>=0?'+':'−'}{formatSAR(Math.abs(member.balance),lang)}</span></div>)}</div><p className="balance-note">{lang==='bn'?'ইতিবাচক = সমান অংশের চেয়ে বেশি পরিশোধ করেছেন।':'Positive means paid more than their equal share.'}</p></article></section>
   <section className="panel recent-panel"><div className="panel-heading"><div><p className="eyebrow">ACTIVITY</p><h2>{t.recent}</h2></div><span className="activity-count">{expenses.length}</span></div>{expenses.length===0?<div className="empty"><span>🧾</span><p>{t.noExpenses}</p></div>:<div className="expense-list">{expenses.map(item=>{const member=members.find(m=>m.id===item.paid_by_member_id);return <div className="expense-row" key={item.id}><span className="expense-icon">🛒</span><span className="expense-info"><strong>{item.description}</strong><small>{member?(lang==='bn'?member.name_bn:member.name):'—'} · {item.expense_date}</small></span><strong className="expense-amount">{formatSAR(Number(item.amount),lang)}</strong><span className="expense-actions"><button type="button" className="text-action" onClick={()=>startEdit(item)} disabled={busy} aria-label={t.editExpense}>{t.edit}</button><button type="button" className="text-action danger-action" onClick={()=>void deleteExpense(item)} disabled={busy} aria-label={t.delete}>{t.delete}</button></span></div>})}</div>}</section>
   {notice&&<p className="balance-note" role="status">{notice}</p>}
  </>}
  {error&&session&&members.length>0&&<p className="error" role="alert">{error}</p>}
  <footer>MealMate <span>·</span> {lang==='bn'?'সমান ভাগ, সহজ হিসাব':'Fair shares. Clear records.'}</footer>
 </main>
}
