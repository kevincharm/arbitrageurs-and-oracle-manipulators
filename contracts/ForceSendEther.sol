pragma solidity ^0.6;

contract ForceSendEther {
    /**
     * Force send to `target` address, even if it's a contract that
     * might revert.
     */
    function forceSend(address payable target) external payable {
        selfdestruct(target);
    }
}
