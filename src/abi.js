export const ABI=[
'function count() view returns (uint256)',
'function credits(address) view returns (uint256)',
'function getAgreement(uint256) view returns ((address client,address contractor,address arbitrator,string title,uint256 deadline,uint256 remaining),(string title,uint256 amount,uint8 status,string evidence)[])',
'function create(address,address,string,uint256,string[],uint256[]) payable returns (uint256)',
'function submit(uint256,uint256,string)','function approve(uint256,uint256)','function dispute(uint256,uint256)','function resolve(uint256,uint256,uint256)','function refundExpired(uint256,uint256)','function withdraw()'];
