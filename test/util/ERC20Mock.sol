import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Table} from "../../src/Table.sol";

contract ERC20Mock is IERC20 {
    function totalSupply() public view returns (uint256) {
        return 0;
    }

    function balanceOf(address owner) public view returns (uint256) {
        return 0;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return 0;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        if (s_reenterClaimRefund) {
            Table(payable(msg.sender)).claimRefund();
            s_reenterClaimRefund = false;
        }
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        return true;
    }

    bool s_reenterClaimRefund;
    function setReenterClaimRefund(bool _reenter) external {
        s_reenterClaimRefund = _reenter;
    }
}