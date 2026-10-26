// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
contract StageLock {
 enum Status { Pending, Submitted, Paid, Disputed, Refunded }
 struct Milestone { string title; uint256 amount; Status status; string evidence; }
 struct Agreement { address client; address contractor; address arbitrator; string title; uint256 deadline; uint256 remaining; }
 Agreement[] private agreements;
 mapping(uint256=>Milestone[]) private milestones;
 mapping(address=>uint256) public credits;
 bool private locked;
 event Created(uint256 indexed id,address indexed client,address indexed contractor);
 event Submitted(uint256 indexed id,uint256 indexed milestone,string evidence);
 event Settled(uint256 indexed id,uint256 indexed milestone,uint256 contractorAmount,uint256 clientAmount);
 event Disputed(uint256 indexed id,uint256 indexed milestone);
 event Withdrawn(address indexed account,uint256 amount);
 function count() external view returns(uint256) { return agreements.length; }
 function getAgreement(uint256 id) external view returns(Agreement memory,Milestone[] memory) { require(id<agreements.length,"Unknown agreement"); return(agreements[id],milestones[id]); }
 function create(address contractor,address arbitrator,string calldata title,uint256 deadline,string[] calldata titles,uint256[] calldata amounts) external payable returns(uint256 id) {
  require(contractor!=address(0)&&arbitrator!=address(0),"Zero address");
  require(contractor!=msg.sender&&arbitrator!=msg.sender&&arbitrator!=contractor,"Distinct parties required");
  require(bytes(title).length>0&&bytes(title).length<=120,"Invalid title");
  require(deadline>block.timestamp&&deadline<=block.timestamp+365 days,"Invalid deadline");
  require(titles.length>0&&titles.length<=12&&titles.length==amounts.length,"Invalid milestones");
  id=agreements.length; uint256 total;
  for(uint256 i;i<titles.length;++i) { require(amounts[i]>0&&bytes(titles[i]).length>0&&bytes(titles[i]).length<=120,"Invalid milestone"); total+=amounts[i]; milestones[id].push(Milestone(titles[i],amounts[i],Status.Pending,"")); }
  require(msg.value==total,"Funding must match total");
  agreements.push(Agreement(msg.sender,contractor,arbitrator,title,deadline,total)); emit Created(id,msg.sender,contractor);
 }
 function submit(uint256 id,uint256 index,string calldata evidence) external {
  Agreement storage a=agreements[id]; Milestone storage m=milestones[id][index];
  require(msg.sender==a.contractor,"Contractor only"); require(block.timestamp<=a.deadline,"Deadline passed"); require(m.status==Status.Pending,"Not pending");
  require(bytes(evidence).length>0&&bytes(evidence).length<=500,"Invalid evidence"); m.evidence=evidence; m.status=Status.Submitted; emit Submitted(id,index,evidence);
 }
 function approve(uint256 id,uint256 index) external { require(msg.sender==agreements[id].client,"Client only"); require(milestones[id][index].status==Status.Submitted,"Not submitted"); _settle(id,index,milestones[id][index].amount); }
 function dispute(uint256 id,uint256 index) external { Agreement storage a=agreements[id]; Milestone storage m=milestones[id][index]; require(msg.sender==a.client||msg.sender==a.contractor,"Party only"); require(m.status==Status.Submitted,"Not submitted"); m.status=Status.Disputed; emit Disputed(id,index); }
 function resolve(uint256 id,uint256 index,uint256 contractorAmount) external { require(msg.sender==agreements[id].arbitrator,"Arbitrator only"); require(milestones[id][index].status==Status.Disputed,"Not disputed"); require(contractorAmount<=milestones[id][index].amount,"Invalid allocation"); _settle(id,index,contractorAmount); }
 function refundExpired(uint256 id,uint256 index) external { require(msg.sender==agreements[id].client,"Client only"); require(block.timestamp>agreements[id].deadline,"Deadline not reached"); require(milestones[id][index].status==Status.Pending,"Not pending"); _settle(id,index,0); }
 function _settle(uint256 id,uint256 index,uint256 contractorAmount) private { Agreement storage a=agreements[id]; Milestone storage m=milestones[id][index]; m.status=contractorAmount==0?Status.Refunded:Status.Paid; a.remaining-=m.amount; credits[a.contractor]+=contractorAmount; credits[a.client]+=m.amount-contractorAmount; emit Settled(id,index,contractorAmount,m.amount-contractorAmount); }
 function withdraw() external { require(!locked,"Reentrant call"); locked=true; uint256 amount=credits[msg.sender]; require(amount>0,"No funds available"); credits[msg.sender]=0; (bool ok,)=msg.sender.call{value:amount}(""); require(ok,"Transfer failed"); locked=false; emit Withdrawn(msg.sender,amount); }
}
