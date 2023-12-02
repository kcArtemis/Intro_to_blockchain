//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "./BLS.sol";
//Rewards and stakes kept track only for oracles, funding is not taken into account in this prototype (should come from HEI's and Clients)


struct Oracle {// Details of each oracle
  uint256 oracNo;
  uint256 individTasks;
  uint256 cluster;
}
struct Cluster {// Cluster of oracles
  uint256 clusterID;
  uint256 oracles;
  uint256 [10] rewards;// dependent on maxClusterSize
  uint256 completedTasks;
  address head;
  uint256 keySubTime;
  uint256[4] pubKey;
}
struct HEI {// HEI Struct
  address HEIAddress; 
  string HEIName;
  uint256 assignedCluster;
  bool authenticated;
  string IPNS;
} 

struct Score { //Scoe for each HEI
  string[10] metricData;
  uint256[10] metrics;
  uint256 aggScore;
}

contract Oracles is BLS {
  uint256 private stakeValue = 100000000000000000; //Stake value, to be used for oracles and maintainer
  uint256 private rewardValue = 10000000000000000; //Reward for completing tasks
  uint256 public heiID = 1;                        //Counter for HEIs
  uint256 public clusterCount = 0;                 //Counter for Clusters
  uint16 private minClusterSize = 4;               //Minimum number of oracles in cluster to do tasks
  uint16 public maxClusterSize = 10;               //Maximum number of oracles per cluster
  uint256 private refreshTime = 604800;            //Time required before the aggregate public key is refreshed
  string private IPNSLink;                         //Shared IPNS link
  address maintainer;                              //Current IPNS maintainer
  
  modifier notOracle() { // Ensure sender is not an oracle
    require(oracle[msg.sender].cluster == 0, "Registration denied, can only register once!");
    _;
  }
  modifier isOracle() { // Ensure sender is an oracle
    require(oracle[msg.sender].cluster != 0, "Operation denied, should be a registered oracle!");
    _;
  }

  modifier stake(uint16 _mul) { // Ensure value sent by sender equals the required stake
    require(msg.value == stakeValue*_mul, "Registration denied, invalid stake amount!");
    _;
  }
  modifier validCluster() {  // Ensure cluster of the oracle is valid
   require(cluster[oracle[msg.sender].cluster].oracles >= minClusterSize,"Cluster is invalid!");
    _;
  }

  mapping(address => HEI) hei;              // Mapping of HEIs by address
  mapping(address => Score) score;          // Mapping to link score to HEI
  mapping(uint256 => Cluster) cluster;      // Mapping to Clusters by number
  mapping(address => Oracle) oracle;        // Mapping to Oracle by address
  mapping(address => uint256) dataCluster;  // Mapping of data to assigned cluster

  constructor() {}

 

  function withdrawReward() isOracle public{ //Oracle withdraw reward for completing tasks
    require(cluster[oracle[msg.sender].cluster].rewards[oracle[msg.sender].oracNo]< cluster[oracle[msg.sender].cluster].completedTasks,"Invalid Cluster!");
    uint amount = cluster[oracle[msg.sender].cluster].completedTasks - cluster[oracle[msg.sender].cluster].rewards[oracle[msg.sender].oracNo];// Count valid tasks
    uint pay = amount*rewardValue; //Amount to pay
    payable(msg.sender).transfer(pay);
    cluster[oracle[msg.sender].cluster].rewards[oracle[msg.sender].oracNo]+= amount;// Update to prevent from double withdraw
  }

  function commitHEIData(
    address _dataOwner,
    address _heID,
    uint256 _metricOrder,
    uint256 _metricScore,
    string calldata _metricData,
    uint256[2] calldata _message,
    uint256[2] calldata _thresSig
  ) public isOracle { //Commit verified data submitted for an HEI by a user
    require(hei[_heID].assignedCluster != 0, "HEI is not being ranked!"); //ensure that hei is registered and is assigned a cluster
    require(dataCluster[_dataOwner] == oracle[msg.sender].cluster, "No such data linked to given cluster!"); //check data is assigned to cluster
    require(cluster[oracle[msg.sender].cluster].keySubTime > block.timestamp,"Have to refresh the public key before proceeding!"); // check key is updated
    require(verifySingle(_thresSig, cluster[oracle[msg.sender].cluster].pubKey, _message), "Invalid signature!"); //verify signature
    score[_heID].metrics[_metricOrder] = _metricScore;
    score[_heID].metricData[_metricOrder] = _metricData; 
    oracle[_dataOwner].individTasks++;
    delete dataCluster[_dataOwner];
  }



  event newData(address sender, uint256 cluster, string IPFS, uint8 _metricOrder);

  function newDataSubmission(
    address _heiID,
    string calldata _IPFSLink,
    uint8 _metricOrder
  ) public {//Submit data regarding an HEI
    require(hei[_heiID].assignedCluster != 0 && dataCluster[msg.sender] == 0, "Invalid request!"); //prevent submission to invalid cluster and prevent DoS through constant requests
    dataCluster[msg.sender] = hei[_heiID].assignedCluster;
    emit newData(msg.sender, hei[_heiID].assignedCluster, _IPFSLink, _metricOrder);
  }

  event gatherMetrics(address hei, uint256 cluster);

  function submitSurveyResult(
    address _heID,
    string calldata _surveyResults,
    uint256 _aggregatedValues,
    uint256[2] memory signature,
    uint256[2] memory message
  ) public isOracle {//Cluster submits the result of the conducted survey
    require(verifySingle(signature, cluster[oracle[msg.sender].cluster].pubKey, message), "Invalid threshold signature!");
    require(hei[_heID].assignedCluster == oracle[msg.sender].cluster, "Invalid HEI selected!");//Ensure assigned cluster submitting
    Score memory tempscore;
    tempscore.metrics[score[_heID].metrics.length - 1] = _aggregatedValues;
    tempscore.metricData[score[_heID].metrics.length - 1] = _surveyResults;
    score[_heID] = tempscore;
    cluster[oracle[msg.sender].cluster].completedTasks += 2;
    emit gatherMetrics(_heID, hei[_heID].assignedCluster);//Notify participants to gather other metrics
  }

  event SurveyTask(uint256 cluster, string hei);

  function initiateSurvey(uint256 _clusterID, address _HEID) public isOracle validCluster{// Cluster requests to initiate a survey for HEI
  //Ensure no cluster assigned, cluster is valid and HEI is authenticated
  require(hei[_HEID].assignedCluster == 0 && oracle[msg.sender].cluster == _clusterID && hei[_HEID].authenticated, "Invalid survey request, revise request!");
  require(cluster[oracle[msg.sender].cluster].keySubTime > block.timestamp,"Have to refresh the public key before proceeding!");
    hei[_HEID].assignedCluster = _clusterID;
    oracle[maintainer].individTasks += 2;//Given two points for sharing the IPNS keys, since hei was authenticated
    emit SurveyTask(_clusterID, hei[_HEID].HEIName);
  }

  event AuthenticationMessage(string heiResult);

  function authenticateHEI(//6
    address _heiID,
    uint256 _result,
    uint256[2] calldata _resultBn,
    uint256[2] calldata _thresSig
  ) public isOracle {//Authenticate an HEI based on submitted data
    //Check correct HEI address provided and that the cluster is valid
    require(_heiID == hei[_heiID].HEIAddress && !hei[_heiID].authenticated && cluster[oracle[msg.sender].cluster].oracles >= minClusterSize, "The specified HEI can not be authenticated!");
    require(cluster[oracle[msg.sender].cluster].keySubTime > block.timestamp,"Have to refresh the public key before proceeding!");
    require(verifySingle(_thresSig, cluster[oracle[msg.sender].cluster].pubKey, _resultBn),"The provided signature details are invalid");
    if (_result > 0) {
      // result is 0 if false, >0 if true
      hei[_heiID].authenticated = true;
      emit AuthenticationMessage("The HEI is registered!");
    } else {
      delete hei[_heiID];
      emit AuthenticationMessage("The HEI is not registered!");
    }
    cluster[oracle[msg.sender].cluster].completedTasks++;
  }

  function submitPubKey(uint256[4] calldata _pubkey) public isOracle {//Upload/update the aggregate public key of a cluster
    require(msg.sender == cluster[oracle[msg.sender].cluster].head, "Only oracle head can submit public key!");//Ensure oracle is submitting key
    oracle[msg.sender].individTasks++;
    cluster[oracle[msg.sender].cluster].keySubTime = block.timestamp + refreshTime ;
    cluster[oracle[msg.sender].cluster].pubKey = _pubkey;
  }

  event AuthenticateHEI(string validationPath, string heiName);

  function registerHEI(string memory _HEIName, string memory _validationPath, string memory _IPNS) public notOracle {//Request registration of HEI
    require(hei[msg.sender].HEIAddress == address(0),"Registration can only be done once at a time!");//Ensure one request by HEI is done
    HEI memory tempHEI;
    tempHEI.HEIName = _HEIName;
    tempHEI.HEIAddress = msg.sender;
    tempHEI.IPNS = _IPNS;
    hei[msg.sender] = tempHEI;
    emit AuthenticateHEI(_validationPath, _HEIName);
  }

  event shareAccess(string peerIDNotification);

  function setIPNSLink(string calldata _IPNSLink) public payable stake(5) isOracle {// Set the IPNS link which is shared by oracles
    require(maintainer == address(0),"Maintainer already exists!"); //Ensure no maintainer already exists
    IPNSLink = _IPNSLink;
    maintainer = msg.sender;
    emit shareAccess("Share peerID with oracles!");
  }

  function registerOracle() public payable stake(1) notOracle  {// Oracle registers to handle oracle tasks
    Oracle memory tempOracle;
    tempOracle.individTasks = 0;
    if (cluster[clusterCount].oracles >= maxClusterSize || clusterCount == 0) {
      generateCluster(msg.sender);
    } else cluster[clusterCount].oracles++;
    tempOracle.cluster = clusterCount;
    tempOracle.oracNo = cluster[clusterCount].oracles-1;
    cluster[clusterCount].rewards[tempOracle.oracNo] = cluster[clusterCount].completedTasks;
    oracle[msg.sender] = tempOracle;
  }

  event NewCluster(uint256 clusterID, address head);

  function generateCluster(address _oracle) internal { // Cluster is generated to include oracles
    clusterCount++;
    Cluster memory tempCluster;
    tempCluster.clusterID = clusterCount;
    tempCluster.oracles = 1;
    tempCluster.completedTasks = 0;
    tempCluster.head = _oracle;
    cluster[clusterCount] = tempCluster;
    emit NewCluster(tempCluster.clusterID, _oracle);
  }
  ////////////////////////////Supplementary functions
  function display(address _heiID) public view returns (string memory, address) {
    return (hei[_heiID].HEIName, hei[_heiID].HEIAddress);
  }

  function getOracleHead(uint256 _clusterCount) public view returns (address, address) {
    return (cluster[oracle[msg.sender].cluster].head, cluster[_clusterCount].head);
  }

  function equals(string memory a, string memory b) public pure returns (bool) {
    if (bytes(a).length != bytes(b).length) {
      return false;
    } else {
      return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
  }
}