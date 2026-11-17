import {describe,expect,it} from 'vitest'
import {MEMBERS,splitEqually} from './split'
describe('equal expense splitting',()=>{
 it('splits an amount equally',()=>expect(splitEqually(100)).toEqual([25,25,25,25]))
 it('keeps every halala using a stable remainder',()=>{const p=splitEqually(1,3);expect(p).toEqual([0.34,0.33,0.33]);expect(p.reduce((a,b)=>a+b,0)).toBe(1)})
 it('rejects invalid amounts and member counts',()=>{expect(()=>splitEqually(0)).toThrow();expect(()=>splitEqually(10,0)).toThrow()})
 it('contains the four agreed members',()=>expect(MEMBERS.map(m=>m.name)).toEqual(['MD ROTON MIAH','AJIBUR RAHMAN','ROBIUL ISLAM','HINDI']))
})
