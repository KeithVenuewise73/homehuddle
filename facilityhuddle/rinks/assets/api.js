(function(g){
 const methods={calendar:['public_facility_calendar',false],slots:['public_open_slots',false],catalog:['rink_catalog',false],workspace:['rink_workspace',true],request:['request_rink_ice',true],award:['award_open_slot',true],cancel:['request_booking_cancellation',true],decide:['decide_cancellation',true],waitlist:['set_facility_waitlist',true],decline:['decline_rink_request',true],withdraw:['withdraw_rink_request',true]};
 let sb;
 function client(){return sb||(sb=g.VW.createClient());}
 async function call(name,args={}){
  if(!g.VW_RINKS?.enabled)throw Error('Online scheduling is awaiting activation. Contact the rink for current availability.');
  if(!methods[name])throw Error('Unknown scheduling action');
  if(methods[name][1]){const {data,error}=await client().auth.getUser();if(error||!data?.user)throw Error('Sign in with your authorized email account.');}
  const {data,error}=await client().rpc(methods[name][0],args);if(error)throw Error('The request could not be completed. '+(error.message||'Please try again.'));return data;
 }
 g.RinkAPI={call,client,enabled:()=>g.VW_RINKS?.enabled===true};
})(window);
