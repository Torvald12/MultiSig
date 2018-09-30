pragma solidity ^0.4.22;

contract owned {
    address public owner;
    mapping (address => uint) public memberId;
    mapping (address => bool) isOwner;

    //Member structure
    struct Member {
      address member;
      string name;
    }

    //Check if a person is member
    modifier onlyMembers {
        require(memberId[msg.sender] != 0);
        _;
    }

    //Check if a member is the owner
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function Constructor() public {
        owner = msg.sender;
        isOwner[owner] = true;
    }
}

contract MultiSig is owned {

    uint public ttl;
    uint public threshold;
    uint public expiredTime;
    uint public addressCounter;
    uint public numberOfVotes;
    uint public currentResult;
    Member[] public members;
    Proposal[] public proposals;
    mapping (address => uint256) public balanceOf;

    //Events
    event ProposalExecuted(uint proposalNumber, uint currentResult, uint numberOfVotes, bool proposalPassed);
    event EtherSending(address from, address etherRecipient, uint etherAmount);

    //Proposal structure
    struct Proposal {
        address recipient;
        uint amount;
        string description;
        bytes32 proposalHash;
        bool executed;
        bool proposalPassed;
        uint numberOfVotes;
        Vote[] votes;
        uint currentResult;
        mapping (address => bool) voted;
    }

    //Vote structure
    struct Vote {
        bool isSupported;
        address voterAddress;
    }

    //Constructor
    function Constructor(uint _threshold, uint256 initialSupply, uint proposalNumber) public {
        addMember(0, "");
        addMember(owner, 'Owner');
        setVotingRules(ttl);
        nulling(proposalNumber);
        threshold = _threshold;
        balanceOf[msg.sender] = initialSupply;
    }

    //Add new member
    function addMember(address memberAddress, string memberName) onlyOwner public {
        uint id = memberId[memberAddress];
        if (id == 0) {
            memberId[memberAddress] = members.length;
            id = members.length + 1;
        }
        members[id] = Member({member: memberAddress, name: memberName});
    }

    //Delete existed member
    function deleteMember(address memberAddress) onlyOwner public {
        require(memberId[memberAddress] != 0);

        for (uint i = memberId[memberAddress]; i < members.length - 1; i++) {
            members[i] = members[i + 1];
        }
        delete members[members.length - 1];
        members.length--;
    }

    //Add proposal in Ether
    function newProposalInEther(address etherRecipient, uint etherAmount, string jobDescription, bytes transactionBytecode) onlyMembers public returns(address, uint, string, bytes) {
        uint proposalId = proposals.length++;
        Proposal storage prop = proposals[proposalId];
        prop.recipient = etherRecipient;
        prop.amount = etherAmount * 1 ether;
        prop.description = jobDescription;
        prop.proposalHash = keccak256(etherRecipient, etherAmount, transactionBytecode);
        prop.executed = false;
        prop.proposalPassed = false;
        prop.numberOfVotes = 0;
        return (etherRecipient, etherAmount, jobDescription, transactionBytecode);
    }

    //Set voting rules
    function setVotingRules(uint _ttl) onlyOwner public {
        ttl = _ttl;
        expiredTime = now + ttl;
    }

    //Voting for a proposal
    function voting(uint proposalNumber, bool isSupported) onlyMembers public returns(uint, uint) {
        Proposal storage prop = proposals[proposalNumber];
        require(!prop.voted[msg.sender]);
        prop.voted[msg.sender] = true;
        prop.numberOfVotes++;
        if (isSupported) {
            prop.currentResult++;
        }
        return (prop.numberOfVotes, prop.currentResult);
    }

    //Reseting of current results
    function zeroing(uint proposalNumber) onlyOwner public {
        Proposal storage prop = proposals[proposalNumber];
        prop.numberOfVotes = 0;
        prop.currentResult = 0;
    }

    //Revoting process
    function revoting(uint proposalNumber, bool isSupported) onlyMembers public returns(uint, uint) {
        Proposal storage prop = proposals[proposalNumber];
        require(prop.voted[msg.sender]);
        prop.voted[msg.sender] = false;
        voting(proposalNumber, isSupported);
        return (prop.numberOfVotes, prop.currentResult);
    }

    //Execute the signatures
    function executeSignatures(uint8[] sigV, bytes32[] sigR, bytes32[] sigS, address destinationAddress, bytes32 message, uint someValue) public returns(address) {
        require(sigR.length == threshold);
        require(sigR.length == sigS.length && sigR.length == sigV.length);
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 txHash = keccak256(byte(0x19), byte(0), destinationAddress, message, prefix, addressCounter, someValue);
        address lastAddress = address(0);
        for (uint i = 0; i < threshold; i++) {
          address recoveredAddress = ecrecover(txHash, sigV[i], sigR[i], sigS[i]);
          require(recoveredAddress > lastAddress && isOwner[recoveredAddress]);
          lastAddress = recoveredAddress;
        }
        addressCounter = addressCounter + 1;
        require(destinationAddress.call.value(someValue)(message));
        return lastAddress;
    }

    // Transfer etherAmount to etherRecipient
    function transferEther(address etherRecipient, uint256 etherAmount) payable public returns (bool success) {
        require(balanceOf[msg.sender] >= etherAmount); // Check if the sender has enough Ether
        require(balanceOf[etherRecipient] + etherAmount >= balanceOf[etherRecipient]); // Check for overflows
        balanceOf[msg.sender] -= etherAmount;
        balanceOf[etherRecipient] += etherAmount;
        return true;
    }

    //Count the votes proposal and execute if there are more than half support votes
    function executeProposal(uint proposalNumber, bytes transactionBytecode) public {
        Proposal storage prop = proposals[proposalNumber];
        require(now > expiredTime && !prop.executed && prop.proposalHash == keccak256(prop.recipient, prop.amount, transactionBytecode));
        if (prop.currentResult > ((prop.numberOfVotes >> 1) + 1)) {
            prop.executed = true;
            require(prop.recipient.call.value(prop.amount)(transactionBytecode));
            prop.proposalPassed = true;
        }
        else {
            prop.proposalPassed = false;
        }
        emit ProposalExecuted(proposalNumber, prop.currentResult, prop.numberOfVotes, prop.proposalPassed);
    }
}
