import {useEffect,useState,type FormEvent,type ReactNode} from 'react'
import type {Session} from '@supabase/supabase-js'
import {supabase} from './lib/supabase'

type Props={children:ReactNode}
type Mode='signin'|'signup'|'reset'

// Never let deployed password-recovery emails fall back to localhost.
const DEPLOYED_APP_URL='https://mealmate-git-feature-multi-team-foundation-stockroom4.vercel.app'

export default function AuthGate({children}:Props){
 const [session,setSession]=useState<Session|null>(null)
 const [ready,setReady]=useState(false)
 const [linked,setLinked]=useState<boolean|null>(null)
 const [mode,setMode]=useState<Mode>('signin')
 const [email,setEmail]=useState('')
 const [password,setPassword]=useState('')
 const [inviteCode,setInviteCode]=useState('')
 const [newPassword,setNewPassword]=useState('')
 const [recovery,setRecovery]=useState(()=>typeof window!=='undefined'&&window.location.hash.includes('type=recovery'))
 const [busy,setBusy]=useState(false)
 const [message,setMessage]=useState('')
 const [error,setError]=useState('')

 useEffect(()=>{
  let active=true
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>{
   if(!active)return
   const valid=next?.user.is_anonymous?null:next
   setSession(valid)
   if(next?.user.is_anonymous)void supabase.auth.signOut()
  })
  void supabase.auth.getSession().then(async({data,error:sessionError})=>{
   if(!active)return
   if(sessionError)setError(sessionError.message)
   if(data.session?.user.is_anonymous){await supabase.auth.signOut();if(active)setSession(null)}
   else if(active)setSession(data.session)
   if(active)setReady(true)
  })
  return ()=>{active=false;subscription.unsubscribe()}
 },[])

 useEffect(()=>{
  let active=true
  async function check(){
   if(!session){setLinked(null);return}
   setLinked(null)
   const {data,error:linkError}=await supabase.rpc('get_mealmate_session_context')
   if(!active)return
   if(linkError){setError(linkError.message);setLinked(false);return}
   setLinked(Array.isArray(data)&&data.length>0)
  }
  void check()
  return ()=>{active=false}
 },[session?.user.id])

 async function submitAuth(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setMessage('')
  const redirectUrl=import.meta.env.DEV?window.location.origin:DEPLOYED_APP_URL
  try{
   const cleanEmail=email.trim().toLowerCase()
   if(mode==='signin'){
    const {data,error:authError}=await supabase.auth.signInWithPassword({email:cleanEmail,password})
    if(authError)throw authError
    setSession(data.session)
   }else if(mode==='signup'){
    if(password.length<10)throw new Error('Use a password with at least 10 characters.')
    const {data,error:authError}=await supabase.auth.signUp({email:cleanEmail,password,options:{emailRedirectTo:redirectUrl}})
    if(authError)throw authError
    if(data.session){setSession(data.session);setMessage('Account created. Continue with your household invitation.')}
    else setMessage('Account created. Check your email, confirm your address, then sign in.')
   }else{
    const {error:authError}=await supabase.auth.resetPasswordForEmail(cleanEmail,{redirectTo:redirectUrl})
    if(authError)throw authError
    setMessage('If an account exists for this email, a password reset link has been sent.')
   }
  }catch(err){setError(err instanceof Error?err.message:'Authentication failed. Please try again.')}
  finally{setBusy(false)}
 }

 async function claimInvitation(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setMessage('')
  try{
   const {error:claimError}=await supabase.rpc('claim_mealmate_invitation',{p_token:inviteCode.trim()})
   if(claimError)throw claimError
   setLinked(true);setMessage('Your account is now linked to your household.')
  }catch(err){setError(err instanceof Error?err.message:'Invitation could not be accepted.')}
  finally{setBusy(false)}
 }

 async function saveNewPassword(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setError('');setMessage('')
  try{
   if(newPassword.length<10)throw new Error('Use a password with at least 10 characters.')
   const {error:updateError}=await supabase.auth.updateUser({password:newPassword})
   if(updateError)throw updateError
   setRecovery(false);setNewPassword('');window.history.replaceState({},document.title,window.location.pathname)
   setMessage('Password updated. You can continue using MealMate.')
  }catch(err){setError(err instanceof Error?err.message:'Unable to update password.')}
  finally{setBusy(false)}
 }

 if(!ready)return <main className="shell auth-shell"><section className="panel auth-panel"><p>Checking your secure sign-in…</p></section></main>
 if(session&&linked===null)return <main className="shell auth-shell"><section className="panel auth-panel"><p>Checking your household account…</p></section></main>
 if(session&&linked&&!recovery)return <>{children}</>
 return <main className="shell auth-shell">
  <header className="topbar"><a className="brand" href="#"><span className="brand-mark">M</span><span><strong>MealMate</strong><small>Private household expenses</small></span></a></header>
  <section className="panel auth-panel">
   <div className="panel-heading"><div><p className="eyebrow">SECURE HOUSEHOLD ACCESS</p><h2>{session?'Join your household':recovery?'Set a new password':mode==='signup'?'Create your account':mode==='reset'?'Reset your password':'Welcome back'}</h2></div><span className="plus">🔐</span></div>
   {session&&!linked&&!recovery?<><p>Your email account is signed in, but it is not linked to a household member yet. Enter the one-time invitation code provided by Roton.</p><form onSubmit={claimInvitation}><label>Household invitation code<input value={inviteCode} onChange={e=>setInviteCode(e.target.value)} autoComplete="off" required placeholder="Paste your invitation code"/></label><button className="primary-btn" type="submit" disabled={busy||!inviteCode.trim()}>{busy?'Verifying…':'Join household'}<span>→</span></button></form><button className="secondary-btn" type="button" onClick={()=>void supabase.auth.signOut()}>Sign out</button></>:recovery?<form onSubmit={saveNewPassword}><label>New password<input type="password" value={newPassword} onChange={e=>setNewPassword(e.target.value)} minLength={10} autoComplete="new-password" required/></label><button className="primary-btn" type="submit" disabled={busy||newPassword.length<10}>{busy?'Updating…':'Update password'}<span>✓</span></button></form>:<><p>{mode==='signup'?'Create your personal account. Roton will provide a one-time invitation to connect it to your household member record.':mode==='reset'?'Enter your account email to receive a password reset link.':'Sign in with the email address and password registered for your household account.'}</p><form onSubmit={submitAuth}><label>Email address<input type="email" value={email} onChange={e=>setEmail(e.target.value)} autoComplete="email" required/></label>{mode!=='reset'&&<label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} minLength={mode==='signup'?10:1} autoComplete={mode==='signup'?'new-password':'current-password'} required/></label>}<button className="primary-btn" type="submit" disabled={busy||!email.trim()||(mode!=='reset'&&!password)}>{busy?'Please wait…':mode==='signup'?'Create account':mode==='reset'?'Send reset link':'Sign in'}<span>→</span></button></form><div className="auth-links">{mode==='signin'?<><button type="button" onClick={()=>{setMode('signup');setError('');setMessage('')}}>Create account</button><button type="button" onClick={()=>{setMode('reset');setError('');setMessage('')}}>Forgot password?</button></>:<button type="button" onClick={()=>{setMode('signin');setError('');setMessage('')}}>Back to sign in</button>}</div></>}
   {message&&<p className="balance-note" role="status">{message}</p>}{error&&<p className="error" role="alert">{error}</p>}
  </section>
  <footer>MealMate · Private household access</footer>
 </main>
}
