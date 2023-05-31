// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

contract IntellectualPropertyContract {
    struct IntellectualProperty {
        string name;
        string description;
        string assetType;
        address payable owner;
        bool licensed;
        bool transferred;
        uint licenseFee;
        uint royaltyPercentage;
    }

    mapping(uint => IntellectualProperty) public intellectualProperties;
    uint public intellectualPropertyCount;

    event IntellectualPropertyCreated(
        uint propertyId,
        string name,
        string description,
        string assetType,
        address owner,
        uint licenseFee,
        uint royaltyPercentage
    );

    event IntellectualPropertyLicensed(
        uint propertyId,
        address licensee,
        uint licenseFee
    );
    event IntellectualPropertyTransferred(uint propertyId, address newOwner);
    event RoyaltyPaid(uint propertyId, address payer, uint amount);

    modifier onlyOwner(uint _propertyId) {
        require(
            msg.sender == intellectualProperties[_propertyId].owner,
            "Only the owner can perform this action"
        );
        _;
    }

    function createIntellectualProperty(
        string memory _name,
        string memory _description,
        string memory _assetType,
        uint _licenseFee,
        uint _royaltyPercentage
    ) external {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_assetType).length > 0, "Asset type cannot be empty");
        require(_licenseFee > 0, "License fee must be greater than 0");
        require(
            _royaltyPercentage >= 0 && _royaltyPercentage <= 100,
            "Royalty percentage must be between 0 and 100"
        );

        uint propertyId = intellectualPropertyCount++;

        IntellectualProperty
            storage intellectualProperty = intellectualProperties[propertyId];
        intellectualProperty.name = _name;
        intellectualProperty.description = _description;
        intellectualProperty.assetType = _assetType;
        intellectualProperty.owner = payable(msg.sender);
        intellectualProperty.licensed = false;
        intellectualProperty.transferred = false;
        intellectualProperty.licenseFee = _licenseFee;
        intellectualProperty.royaltyPercentage = _royaltyPercentage;

        emit IntellectualPropertyCreated(
            propertyId,
            _name,
            _description,
            _assetType,
            msg.sender,
            _licenseFee,
            _royaltyPercentage
        );
    }

    function licenseIntellectualProperty(uint _propertyId) external payable {
        IntellectualProperty
            storage intellectualProperty = intellectualProperties[_propertyId];
        require(
            !intellectualProperty.licensed,
            "Intellectual property is already licensed"
        );
        require(
            msg.value == intellectualProperty.licenseFee,
            "Incorrect license fee amount"
        );

        intellectualProperty.owner.transfer(msg.value);
        intellectualProperty.licensed = true;

        emit IntellectualPropertyLicensed(_propertyId, msg.sender, msg.value);
    }

    function updateIntellectualProperty(
        uint _propertyId,
        string memory _name,
        string memory _description,
        string memory _assetType,
        uint _licenseFee,
        uint _royaltyPercentage
    ) external onlyOwner(_propertyId) {
        IntellectualProperty
            storage intellectualProperty = intellectualProperties[_propertyId];
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_assetType).length > 0, "Asset type cannot be empty");
        require(_licenseFee > 0, "License fee must be greater than 0");
        require(
            _royaltyPercentage >= 0 && _royaltyPercentage <= 100,
            "Royalty percentage must be between 0 and 100"
        );

        intellectualProperty.name = _name;
        intellectualProperty.description = _description;
        intellectualProperty.assetType = _assetType;
        intellectualProperty.licenseFee = _licenseFee;
        intellectualProperty.royaltyPercentage = _royaltyPercentage;
    }

    function revokeLicense(uint _propertyId) external onlyOwner(_propertyId) {
        IntellectualProperty
            storage intellectualProperty = intellectualProperties[_propertyId];
        require(
            intellectualProperty.licensed,
            "Intellectual property is not licensed"
        );

        intellectualProperty.licensed = false;

        // Additional logic can be added here to handle any necessary actions upon license revocation
        // Emit an event to indicate that the license has been revoked
    }

    function getLicensedProperties() external view returns (uint[] memory) {
        uint[] memory licensedPropertyIds = new uint[](
            intellectualPropertyCount
        );
        uint count = 0;

        for (uint i = 0; i < intellectualPropertyCount; i++) {
            if (intellectualProperties[i].licensed) {
                licensedPropertyIds[count] = i;
                count++;
            }
        }

        // Resize the array to remove any empty slots
        uint[] memory result = new uint[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = licensedPropertyIds[i];
        }

        return result;
    }

    function getRoyaltyPayments(uint _propertyId) external view returns (uint) {
        uint royaltyPayments = 0;

        // Iterate over the RoyaltyPaid events and calculate the total royalty amount
        for (uint i = 0; i < intellectualPropertyCount; i++) {
            if (intellectualProperties[i].licensed && i == _propertyId) {
                // Calculate the royalty amount based on the percentage and the value paid for royalties
                uint royaltyAmount = (intellectualProperties[i].licenseFee *
                    intellectualProperties[i].royaltyPercentage) / 100;
                royaltyPayments += royaltyAmount;
            }
        }

        return royaltyPayments;
    }

    function getOwnedProperties(
        address _owner
    ) external view returns (uint[] memory) {
        uint[] memory ownedPropertyIds = new uint[](intellectualPropertyCount);
        uint count = 0;

        for (uint i = 0; i < intellectualPropertyCount; i++) {
            if (intellectualProperties[i].owner == _owner) {
                ownedPropertyIds[count] = i;
                count++;
            }
        }

        // Resize the array to remove any empty slots
        uint[] memory result = new uint[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = ownedPropertyIds[i];
        }

        return result;
    }

    function transferIntellectualProperty(
        uint _propertyId,
        address payable _newOwner
    ) external onlyOwner(_propertyId) {
        IntellectualProperty
            storage intellectualProperty = intellectualProperties[_propertyId];
        require(
            !intellectualProperty.transferred,
            "Intellectual property is already transferred"
        );

        intellectualProperty.owner = _newOwner;
        intellectualProperty.transferred = true;

        emit IntellectualPropertyTransferred(_propertyId, _newOwner);
    }

    function payRoyalties(uint _propertyId) external payable {
        IntellectualProperty
            storage intellectualProperty = intellectualProperties[_propertyId];
        require(
            intellectualProperty.licensed,
            "Intellectual property is not licensed"
        );
        require(
            intellectualProperty.owner != msg.sender,
            "The owner cannot pay royalties to themselves"
        );

        uint royaltyAmount = (msg.value *
            intellectualProperty.royaltyPercentage) / 100;
        intellectualProperty.owner.transfer(royaltyAmount);

        emit RoyaltyPaid(_propertyId, msg.sender, royaltyAmount);
    }

    function getPropertyInfo(
        uint _propertyId
    )
        external
        view
        returns (
            string memory name,
            string memory description,
            string memory assetType,
            address owner,
            bool licensed,
            bool transferred,
            uint licenseFee,
            uint royaltyPercentage
        )
    {
        IntellectualProperty
            storage intellectualProperty = intellectualProperties[_propertyId];
        return (
            intellectualProperty.name,
            intellectualProperty.description,
            intellectualProperty.assetType,
            intellectualProperty.owner,
            intellectualProperty.licensed,
            intellectualProperty.transferred,
            intellectualProperty.licenseFee,
            intellectualProperty.royaltyPercentage
        );
    }
}
