// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract AddressStorage {
    error AddressStorage__ZeroAddress();

    mapping(bytes32 => address) private s_addresses;

    function _setAddress(bytes32 _key, address _value) internal {
        if (_value == address(0)) {
            revert AddressStorage__ZeroAddress();
        }
        s_addresses[_key] = _value;
    }

    function getAddress(bytes32 _key) public view returns (address) {
        return s_addresses[_key];
    }
}
