	// SPDX-License-Identifier: MIT
	pragma solidity ^0.8.19;
	
	import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
	import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
	import "@openzeppelin/contracts/security/Pausable.sol";
	import "@openzeppelin/contracts/access/AccessControl.sol";
	import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
	import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
	import "@openzeppelin/contracts/utils/Counters.sol";
	
	contract IntellectualPropertyContract is
	    Initializable,
	    ReentrancyGuard,
	    Pausable,
	    AccessControl,
	    ERC2771Context
	{
	    using Counters for Counters.Counter;
	    using SafeERC20 for IERC20;
	
	    // Constants
	    uint256 public constant VERSION = 1;
	    uint256 private constant BATCH_LIMIT = 50;
	    uint256 private constant MAX_LICENSE_FEE = 1000 ether;
	    uint256 private constant MAX_DESCRIPTION_LENGTH = 1000;
	    uint256 private constant MAX_NAME_LENGTH = 100; 
	    uint256 private constant MAX_REVENUE_SHARES = 10;
	    uint256 private constant MAX_TOTAL_REVENUE_PERCENTAGE = 100;
	    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
	    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
	
	    // Counters
	    Counters.Counter private _propertyIds;
	    Counters.Counter private _disputeIds;
	
	    // Custom Errors
	    error InvalidInput();
	    error Unauthorized();
	    error PaymentFailed();
	    error LicenseExpired();
	    error DisputeActive();
	    error BatchLimitExceeded();
	    error TimeLockActive();
	
	    // Structs
	    struct IntellectualProperty {
	        string name;
	        string description;
	        string assetType;
	        address payable owner;
	        bool licensed;
	        bool transferred;
	        uint256 licenseFee;
	        uint256 royaltyPercentage;
	        uint256 createdAt;
	        string[] allowedUsages;
	        bool disputeActive;
	    }
	
	    struct License {
	        address licensee;
	        uint256 startTime;
	        uint256 duration;
	        bool active;
	        string terms;
	        bool renewable;
	        bool transferable;
	        uint256 maxUsers;
	        mapping(address => bool) authorizedUsers;
	    }
	
	    struct Dispute {
	        uint256 id;
	        address initiator;
	        string description;
	        bool resolved;
	        uint256 createdAt;
	        mapping(address => bool) votes;
	        uint256 votesCount;
	    }
	
	    struct RevenueShare {
	        address payable beneficiary;
	        uint256 percentage;
	        bool active;
	    }
	
	    struct TimeLock {
	        uint256 releaseTime;
	        bytes32 operationHash;
	        bool executed;
	    }
	
	    // Mappings
	    mapping(uint256 => IntellectualProperty) public intellectualProperties;
	    mapping(uint256 => mapping(address => License)) public licenses;
	    mapping(uint256 => Dispute[]) public propertyDisputes;
	    mapping(uint256 => RevenueShare[]) public propertyRevenueShares;
	    mapping(bytes32 => TimeLock) public timelocks;
	    mapping(uint256 => uint256[]) private propertyBatches;
	    mapping(uint256 => string) public upgradeHistory;
	    mapping(address => uint256) public userOperationCount;
	    mapping(uint256 => uint256) public propertyRevenue;
	
	    // Events
	    event IntellectualPropertyCreated(
	        uint256 indexed propertyId,
	        string name,
	        string description,
	        string assetType,
	        address indexed owner,
	        uint256 licenseFee,
	        uint256 royaltyPercentage
	    );
	    event IntellectualPropertyLicensed(
	        uint256 indexed propertyId,
	        address indexed licensee,
	        uint256 licenseFee,
	        uint256 duration
	    );
	    event IntellectualPropertyTransferred(
	        uint256 indexed propertyId,
	        address indexed previousOwner,
	        address indexed newOwner
	    );
	    event RoyaltyPaid(
	        uint256 indexed propertyId,
	        address indexed payer,
	        uint256 amount
	    );
	    event LicenseRevoked(
	        uint256 indexed propertyId,
	        address indexed licensee,
	        uint256 timestamp
	    );
	    event PropertyUpdated(
	        uint256 indexed propertyId,
	        string name,
	        uint256 licenseFee,
	        uint256 royaltyPercentage
	    );
	    event DisputeCreated(
	        uint256 indexed propertyId,
	        uint256 indexed disputeId,
	        address initiator
	    );
	    event DisputeResolved(uint256 indexed propertyId, uint256 indexed disputeId);
	    event RevenueShareAdded(
	        uint256 indexed propertyId,
	        address indexed beneficiary,
	        uint256 percentage
	    );
	    event PaymentReceived(address indexed from, uint256 amount);
	event EmergencyWithdraw(address indexed admin, uint256 amount);
	event LicenseRenewed(uint256 indexed propertyId, address indexed licensee, uint256 duration);
	event RefundProcessed(uint256 indexed propertyId, address indexed to, uint256 amount);
	    event TimeLockCreated(bytes32 indexed operationHash, uint256 releaseTime);
	    event BatchOperationCompleted(uint256 indexed batchId, uint256 count);
	
	    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) {
	        _disableInitializers();
	    }
	
	    function initialize() public initializer {
	        __Pausable_init();
	        
	        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
	        _setupRole(ADMIN_ROLE, _msgSender());
	        
	        upgradeHistory[VERSION] = "Initial version";
	    }
	
	    // Modifiers
	    modifier onlyOwner(uint256 _propertyId) {
	        if (_msgSender() != intellectualProperties[_propertyId].owner)
	            revert Unauthorized();
	        _;
	    }
	
	    modifier validPropertyId(uint256 _propertyId) {
	        if (_propertyId >= _propertyIds.current()) revert InvalidInput();
	        _;
	    }
	
	    modifier rateLimited() {
	        uint256 userOps = userOperationCount[_msgSender()]++;
	        if (userOps >= 100) revert("Rate limit exceeded");
	        _;
	    }
	
	    // Main Functions 
	
	    function createIntellectualProperty(
	        string memory _name,
	        string memory _description,
	        string memory _assetType,
	        uint256 _licenseFee,
	        uint256 _royaltyPercentage,
	        string[] memory _allowedUsages
	    ) external whenNotPaused nonReentrant rateLimited {
	        if (bytes(_name).length > MAX_NAME_LENGTH ||
	            bytes(_description).length > MAX_DESCRIPTION_LENGTH ||
	            _licenseFee > MAX_LICENSE_FEE ||
	            _royaltyPercentage > 100)
	            revert InvalidInput();
	
	        uint256 propertyId = _propertyIds.current();
	        _propertyIds.increment();
	
	        IntellectualProperty storage newProperty = intellectualProperties[propertyId];
	        newProperty.name = _name;
	        newProperty.description = _description;
	        newProperty.assetType = _assetType;
	        newProperty.owner = payable(_msgSender());
	        newProperty.licenseFee = _licenseFee;
	        newProperty.royaltyPercentage = _royaltyPercentage;
	        newProperty.createdAt = block.timestamp;
	        newProperty.allowedUsages = _allowedUsages;
	
	        emit IntellectualPropertyCreated(
	            propertyId,
	            _name,
	            _description,
	            _assetType,
	            _msgSender(),
	            _licenseFee,
	            _royaltyPercentage
	        );
	    }
	
	    function licenseIntellectualProperty(
	        uint256 _propertyId,
	        uint256 _duration,
	        bool _renewable,
	        uint256 _maxUsers
	    ) external payable whenNotPaused nonReentrant validPropertyId(_propertyId) {
	        IntellectualProperty storage property = intellectualProperties[_propertyId];
	        
	        if (property.disputeActive) revert DisputeActive();
	        if (msg.value != property.licenseFee) revert InvalidInput();
	
	        License storage newLicense = licenses[_propertyId][_msgSender()];
	        newLicense.licensee = _msgSender();
	        newLicense.startTime = block.timestamp;
	        newLicense.duration = _duration;
	        newLicense.active = true;
	        newLicense.renewable = _renewable;
	        newLicense.maxUsers = _maxUsers;
	
	        // Handle payment distribution
	        _distributePayment(_propertyId, msg.value);
	
	        emit IntellectualPropertyLicensed(
	            _propertyId,
	            _msgSender(),
	            msg.value,
	            _duration
	        );
	    }
	
	    function _distributePayment(uint256 _propertyId, uint256 _amount) internal {
	        IntellectualProperty storage property = intellectualProperties[_propertyId];
	        RevenueShare[] storage shares = propertyRevenueShares[_propertyId];
	
	        uint256 remainingAmount = _amount;
	        
	        // Distribute to revenue share beneficiaries
	        for (uint256 i = 0; i < shares.length; i++) {
	            if (shares[i].active) {
	                uint256 shareAmount = (_amount * shares[i].percentage) / 100;
	                remainingAmount -= shareAmount;
	                (bool success, ) = shares[i].beneficiary.call{value: shareAmount}("");
	                if (!success) revert PaymentFailed();
	            }
	        }
	
	        // Send remaining amount to property owner
	        (bool success, ) = property.owner.call{value: remainingAmount}("");
	        if (!success) revert PaymentFailed();
	
	        propertyRevenue[_propertyId] += _amount;
	    }
	
	    function batchCreateProperties(
	        string[] memory _names,
	        string[] memory _descriptions,
	        string[] memory _assetTypes,
	        uint256[] memory _licenseFees,
	        uint256[] memory _royaltyPercentages,
	        string[][] memory _allowedUsages
	    ) external whenNotPaused nonReentrant {
	        if (_names.length > BATCH_LIMIT) revert BatchLimitExceeded();
	        if (_names.length != _descriptions.length ||
	            _names.length != _assetTypes.length ||
	            _names.length != _licenseFees.length ||
	            _names.length != _royaltyPercentages.length ||
	            _names.length != _allowedUsages.length)
	            revert InvalidInput();
	
	        uint256[] memory batchIds = new uint256[](_names.length);
	        
	        for (uint256 i = 0; i < _names.length; i++) {
	            batchIds[i] = _propertyIds.current();
	            createIntellectualProperty(
	                _names[i],
	                _descriptions[i],
	                _assetTypes[i],
	                _licenseFees[i],
	                _royaltyPercentages[i],
	                _allowedUsages[i]
	            );
	        }
	
	        propertyBatches[block.timestamp] = batchIds;
	        emit BatchOperationCompleted(block.timestamp, _names.length);
	    }
	
	    function isLicenseExpired(uint256 _propertyId, address _licensee) public view returns (bool) {
	    License storage license = licenses[_propertyId][_licensee];
	    return license.startTime + license.duration < block.timestamp;
	    }
	
	    function renewLicense(uint256 _propertyId) external payable whenNotPaused nonReentrant {
	    License storage license = licenses[_propertyId][_msgSender()];
	    require(license.renewable, "License not renewable");
	    require(isLicenseExpired(_propertyId, _msgSender()), "License not expired");
	    
	    IntellectualProperty storage property = intellectualProperties[_propertyId];
	    require(msg.value == property.licenseFee, "Incorrect renewal fee");
	    
	    license.startTime = block.timestamp;
	    _distributePayment(_propertyId, msg.value);
	    
	    emit LicenseRenewed(_propertyId, _msgSender(), license.duration);
	    }
	
	    function createDispute(
	        uint256 _propertyId,
	        string memory _description
	    ) external whenNotPaused validPropertyId(_propertyId) {
	        IntellectualProperty storage property = intellectualProperties[_propertyId];
	        if (!licenses[_propertyId][_msgSender()].active &&
	            property.owner != _msgSender())
	            revert Unauthorized();
	
	        uint256 disputeId = _disputeIds.current();
	        _disputeIds.increment();
	
	        Dispute storage dispute = propertyDisputes[_propertyId].push();
	        dispute.id = disputeId;
	        dispute.initiator = _msgSender();
	        dispute.description = _description;
	        dispute.createdAt = block.timestamp;
	        
	        property.disputeActive = true;
	
	        emit DisputeCreated(_propertyId, disputeId, _msgSender());
	    }
	
	    function addRevenueShare(
	    uint256 _propertyId,
	    address payable _beneficiary,
	    uint256 _percentage) external whenNotPaused nonReentrant onlyOwner(_propertyId) {
	    require(_beneficiary != address(0), "Invalid beneficiary address");
	    require(_percentage > 0 && _percentage <= 100, "Invalid percentage");
	    
	    RevenueShare[] storage shares = propertyRevenueShares[_propertyId];
	    require(shares.length < MAX_REVENUE_SHARES, "Too many revenue shares");
	    
	    // Calculate total percentage including new share
	    uint256 totalPercentage = _percentage;
	    for(uint256 i = 0; i < shares.length; i++) {
	        if(shares[i].active) {
	            totalPercentage += shares[i].percentage;
	        }
	    }
	    require(totalPercentage <= MAX_TOTAL_REVENUE_PERCENTAGE, "Total percentage exceeds 100%");
	
	    RevenueShare memory share = RevenueShare({
	        beneficiary: _beneficiary,
	        percentage: _percentage,
	        active: true
	    });
	
	    propertyRevenueShares[_propertyId].push(share);
	    emit RevenueShareAdded(_propertyId, _beneficiary, _percentage);
	    }
	
	    function createTimeLock(
	        bytes32 _operationHash,
	        uint256 _delay
	    ) external onlyRole(ADMIN_ROLE) {
	        TimeLock storage lock = timelocks[_operationHash];
	        lock.releaseTime = block.timestamp + _delay;
	        lock.operationHash = _operationHash;
	        
	        emit TimeLockCreated(_operationHash, lock.releaseTime);
	    }
	
	    // Admin Functions
	
	    function pause() external onlyRole(ADMIN_ROLE) {
	        _pause();
	    }
	
	    function unpause() external onlyRole(ADMIN_ROLE) {
	        _unpause();
	    }
	
	    function updateUpgradeHistory(
	        uint256 _version,
	        string memory _description
	    ) external onlyRole(ADMIN_ROLE) {
	        upgradeHistory[_version] = _description;
	    }
	
	    // View Functions
	
	    function getPropertyInfo(
	        uint256 _propertyId
	    )
	        external
	        view
	        validPropertyId(_propertyId)
	        returns (
	            string memory name,
	            string memory description,
	            string memory assetType,
	            address owner,
	            bool licensed,
	            bool transferred,
	            uint256 licenseFee,
	            uint256 royaltyPercentage,
	            uint256 createdAt,
	            string[] memory allowedUsages,
	            bool disputeActive
	        )
	    {
	        IntellectualProperty storage property = intellectualProperties[_propertyId];
	        return (
	            property.name,
	            property.description,
	            property.assetType,
	            property.owner,
	            property.licensed,
	            property.transferred,
	            property.licenseFee,
	            property.royaltyPercentage,
	            property.createdAt,
	            property.allowedUsages,
	            property.disputeActive
	        );
	    }
	
	    function transferIntellectualProperty(
	    uint256 _propertyId,
	    address payable _newOwner
	    p) 
	    external 
	    whenNotPaused 
	    nonReentrant 
	    onlyOwner(_propertyId) 
	    {
	    require(_newOwner != address(0), "Invalid new owner address");
	    
	    IntellectualProperty storage property = intellectualProperties[_propertyId];
	    if (property.disputeActive) revert DisputeActive();
	    
	    // If high-value property, check timelock
	    if (property.licenseFee >= 100 ether) {
	        bytes32 operationHash = keccak256(
	            abi.encodePacked(_propertyId, _newOwner, block.timestamp)
	        );
	        TimeLock storage lock = timelocks[operationHash];
	        if (!lock.executed && lock.releaseTime > block.timestamp) 
	            revert TimeLockActive();
	        lock.executed = true;
	    }
	
	    address previousOwner = property.owner;
	    property.owner = _newOwner;
	    property.transferred = true;
	
	    emit IntellectualPropertyTransferred(
	        _propertyId, 
	        previousOwner, 
	        _newOwner
	    );
	    }
	
	    function payRoyalties(
	        uint256 _propertyId
	    ) 
	        external 
	        payable 
	        whenNotPaused 
	        nonReentrant 
	    {
	        IntellectualProperty storage property = intellectualProperties[_propertyId];
	        if (!licenses[_propertyId][_msgSender()].active) 
	            revert Unauthorized();
	        if (property.disputeActive) 
	            revert DisputeActive();
	
	        uint256 royaltyAmount = (msg.value * property.royaltyPercentage) / 100;
	        _distributePayment(_propertyId, royaltyAmount);
	
	        emit RoyaltyPaid(_propertyId, _msgSender(), royaltyAmount);
	    }
	
	    function resolveDispute(
	    uint256 _propertyId,
	    uint256 _disputeId,
	    bool _refundRequired
	    ) 
	    external 
	    whenNotPaused 
	    nonReentrant 
	    {
	    if (!hasRole(MODERATOR_ROLE, _msgSender()) && 
	        !hasRole(ADMIN_ROLE, _msgSender())) 
	        revert Unauthorized();
	
	    IntellectualProperty storage property = intellectualProperties[_propertyId];
	    Dispute[] storage disputes = propertyDisputes[_propertyId];
	    
	    bool found = false;
	    uint256 disputeIndex;
	    for (uint256 i = 0; i < disputes.length; i++) {
	        if (disputes[i].id == _disputeId && !disputes[i].resolved) {
	            disputeIndex = i;
	            found = true;
	            break;
	        }
	    }
	    
	    if (!found) revert InvalidInput();
	    
	    disputes[disputeIndex].resolved = true;
	    property.disputeActive = false;
	    
	    if (_refundRequired) {
	        License storage license = licenses[_propertyId][disputes[disputeIndex].initiator];
	        if (license.active) {
	            uint256 refundAmount = property.licenseFee;
	            license.active = false;
	            
	            (bool success, ) = disputes[disputeIndex].initiator.call{value: refundAmount}("");
	            require(success, "Refund failed");
	            
	            emit RefundProcessed(_propertyId, disputes[disputeIndex].initiator, refundAmount);
	        }
	    }
	    
	    emit DisputeResolved(_propertyId, _disputeId);
	    }
	
	    // Override required functions
	    function _msgSender() internal view override(Context, ERC2771Context)
	        returns (address sender) {
	        return ERC2771Context._msgSender();
	    }
	
	    function _msgData() internal view override(Context, ERC2771Context)
	        returns (bytes calldata) {
	        return ERC2771Context._msgData();
	    }
	
	    function emergencyWithdraw() external onlyRole(ADMIN_ROLE) {
	    uint256 balance = address(this).balance;
	    (bool success, ) = _msgSender().call{value: balance}("");
	    require(success, "Withdrawal failed");
	    emit EmergencyWithdraw(_msgSender(), balance);
	    }
	    