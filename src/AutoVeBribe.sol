import {ProtocolTimeLibrary} from "./libraries/ProtocolTimeLibrary.sol";

contract AutoVeBribe {
    bool initialized;
    address public gauge;

    error AlreadyInitialized();
    function initialize(address _gauge) external {
        if(initialized) revert AlreadyInitialized();
        gauge = _gauge;
    }
}