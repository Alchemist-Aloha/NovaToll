import assert from 'node:assert/strict';
import worker from '../worker/index.js';
const original=globalThis.fetch;
const url='https://test/api/prices?road=66&dir=Westbound&entry=16&exits=1';
try{
 let calls=0;
 globalThis.fetch=async()=>++calls===1?new Response('Unavailable',{status:503}):Response.json({decToll:12.5});
 let result=await(await worker.fetch(new Request(url))).json();assert.equal(calls,2);assert.equal(result.quotes[0].price,12.5);assert.equal(result.quotes[0].dataSource,'VDOT current I-66 calculator');
 calls=0;globalThis.fetch=async()=>{calls++;return Response.json({decToll:null});};result=await(await worker.fetch(new Request(url))).json();assert.equal(calls,2);assert.equal(result.quotes[0].price,undefined);assert.match(result.quotes[0].error,/unavailable/);
 globalThis.fetch=async()=>Response.json({decToll:0});result=await(await worker.fetch(new Request(url))).json();assert.equal(result.quotes[0].price,0);
 console.log('I-66 checks passed: transient failure retries, invalid data stays unavailable, genuine zero rate preserved.');
}finally{globalThis.fetch=original;}
