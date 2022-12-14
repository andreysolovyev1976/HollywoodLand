//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


/**
* @dev It is a development of ERC20Votes contract from OZ
     * it allows to have a multiple projects, where it is not allowed to have votes move between the projects.
     */


import "./GovernanceTokenStorage.sol";
import "../../NFT/Libs/NFTStructs.sol";

import "../../Libs/ERC777_SenderRecipient.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


//todo: consider deleting ERC20Permit from inheritance DAG


contract GovernanceTokenImplementation is ExternalGovernanceTokenStorage, ERC20Permit, AccessControl, Initializable, ERC777SenderRecipientMock {
    using SafeMath for uint256;

    modifier isSetupOk() {
        require(
            address(m_token) != address(0) &&
            address(m_nft_catalog) != address(0) &&
            address(m_nft_ownership) != address(0) &&
            address(m_project_catalog) != address(0) &&
            m_company_account != address(0)

        , "Setup is not ok GT");
        _;
    }

    constructor()
    ERC20("Governance Token Implementation, not for use", "DONT_USE") //name, symbol
    ERC20Permit("Governance Token Implementation, not for use")
    {}

    function initialize(string memory version) public initializer onlyRole(MINTER_ROLE) {
        m_implementation_version.push(version);
    }
    //name()
    //symbol()
    function getCurrentVersion () public view returns (string memory) {
        return m_implementation_version[m_implementation_version.length - 1];
    }
    function getVersionHistory () public view returns (string[] memory) {
        return m_implementation_version;
    }


    function setERC777 (address token) public onlyRole(MINTER_ROLE) {
        require (token != address(0), "Address should be valid");
        m_token = IERC777Wrapper(token);
        emit ERC777Set(token);
    }
    function setNFTCatalog (address nft_catalog) public onlyRole(MINTER_ROLE) {
        require (nft_catalog != address(0), "Address should be valid");
        m_nft_catalog = INFTCatalog(nft_catalog);
        emit NFTCatalogSet(nft_catalog);
    }
    function setNFTOwnership (address nft_ownership) public onlyRole(MINTER_ROLE) {
        require (nft_ownership != address(0), "no address");
        m_nft_ownership = INFTOwnership(nft_ownership);
        emit NFTOwnershipSet(nft_ownership);
    }
    function setProjectCatalog (address project_catalog) public onlyRole(MINTER_ROLE) {
        require (project_catalog != address(0), "Address should be valid");
        m_project_catalog = IProjectCatalog(project_catalog);
        emit ProjectCatalogSet(project_catalog);
    }
    function setCompanyAccount (address company_account) public onlyRole(MINTER_ROLE) {
        require (company_account != address(0), "Address should be valid");
        m_company_account = company_account;
        emit CompanyAccountSet(m_company_account);
    }

    function getAddress () public view returns (address) {
        return address(this);
    }

    /// these funcs are from ERCWrapper @OZ contracts/token/ERC20/extensions/ERC20Wrapper.sol

    /**
     * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
     */
    /**
    function depositFor(address account, uint256 amount) public virtual returns (bool) {
        SafeERC20.safeTransferFrom(m_token, _msgSender(), address(this), amount);
        _mint(account, amount);
        return true;
    }
    */
    /**
     * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
     */
    /**
    function withdrawTo(address account, uint256 amount) public virtual returns (bool) {
        _burn(_msgSender(), amount);
        SafeERC20.safeTransfer(m_token, account, amount);
        return true;
    }
    */

    /**
     * @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake. Internal
     * function that can be exposed with access control if desired.
     */
    /**
    function _recover(address account) internal virtual returns (uint256) {
        uint256 value = m_token.balanceOf(address(this)) - totalSupply();
        _mint(account, value);
        return value;
    }
    */

    function depositTokens(address account, uint256 amount, uint256 project_id) public isSetupOk returns (bool) {
        if (project_id != COMMON_ISSUES_UID){
            NFTStructs.NFT memory project = m_nft_catalog.getNFT(project_id);
            require (project._type == NFTStructs.NftType.Project, "Can't deposit for a non-Project");
            require (m_project_catalog.projectExists(project_id));
        }
        require (m_token.isOperatorFor(msg.sender, account), "Sender is not an operator for the account");
        m_token.operatorSend(account, m_company_account, amount, '', '');
        _mint(account, project_id, amount);

        m_deposits[account][project_id]._gov_tokens =
            m_deposits[account][project_id]._gov_tokens.add(amount);
        m_deposits[account][project_id]._gov_tokens_by_native_token =
            m_deposits[account][project_id]._gov_tokens_by_native_token.add(amount);

        emit TokensDeposited(account, project_id, amount);

    return true;
    }
    function depositNFTs(address account, uint256 token_id, uint256 project_id) public isSetupOk returns (bool) {
        require(
            m_nft_ownership.isApprovedOperator(account, msg.sender) ||
            m_nft_ownership.isApprovedOperator(account, msg.sender, token_id)
            , "not approved by Governance Token");

        NFTStructs.NFT memory nft = m_nft_catalog.getNFT(token_id);
        require (nft._type != NFTStructs.NftType.Project, "Can't deposit a Project");

        if (project_id != COMMON_ISSUES_UID){
            NFTStructs.NFT memory project = m_nft_catalog.getNFT(project_id);
            require (project._type == NFTStructs.NftType.Project, "Can't deposit for a non-Project");
            require (m_project_catalog.projectExists(project_id));

            uint256 stored_project_id = m_nft_catalog.getProjectOfToken(token_id);
            require (stored_project_id == project_id, "Token is not owned by this project");
        }

        require (nft._last_price != 0, "NFT has not yet been a subject of a sale, can't deposit 0");

        uint256 shares_available = m_nft_ownership.getSharesAvailable(account, token_id);
        uint256 shares_total = m_nft_ownership.getTotalSharesForNFT(token_id);
        uint256 governance_tokens = nft._last_price.mul(shares_available).div(shares_total);

        uint256 tx_id = m_nft_catalog.approveTransaction(account, m_company_account, token_id, shares_available, 0, false);
        m_nft_catalog.implementTransaction(tx_id);

        _mint(account, project_id, governance_tokens);

        m_deposits[account][project_id]._gov_tokens =
            m_deposits[account][project_id]._gov_tokens.add(governance_tokens);
        m_deposits[account][project_id]._gov_tokens_by_nfts[token_id]._tokens_issued =
            m_deposits[account][project_id]._gov_tokens_by_nfts[token_id]._tokens_issued.add(governance_tokens);
        m_deposits[account][project_id]._gov_tokens_by_nfts[token_id]._shares_deposited =
            m_deposits[account][project_id]._gov_tokens_by_nfts[token_id]._shares_deposited.add(shares_available);

        IterableSet.insert(m_deposits[account][project_id]._nfts, token_id);


        emit NFTsDeposited(account, project_id, token_id, governance_tokens);
        return true;
    }
    function withdrawTokens(address account, uint256 amount, uint256 project_id) public virtual isSetupOk returns (bool) {
        if (project_id != COMMON_ISSUES_UID){
            require (m_project_catalog.projectExists(project_id));
        }

        require (m_deposits[account][project_id]._gov_tokens_by_native_token >= amount, "Not enough tokens");
        m_token.operatorSend(m_company_account, account, amount, '', '');
        _burn(account, project_id, amount);

        m_deposits[account][project_id]._gov_tokens =
            m_deposits[account][project_id]._gov_tokens.sub(amount);
        m_deposits[account][project_id]._gov_tokens_by_native_token =
            m_deposits[account][project_id]._gov_tokens_by_native_token.sub(amount);

        emit TokensWithdrawn(account, project_id, amount);
        return true;
    }
    function withdrawNFTs(address account, uint256 token_id, uint256 project_id) public virtual isSetupOk returns (bool) {

        require(
            m_nft_ownership.isApprovedOperator(account, msg.sender) ||
            m_nft_ownership.isApprovedOperator(account, msg.sender, token_id)
        , "not approved by Governance Token");

        bool is_deposited = IterableSet.inserted(m_deposits[account][project_id]._nfts, token_id);
        require (is_deposited, "NFT is not deposited");

        uint256 shares_available = m_deposits[account][project_id]._gov_tokens_by_nfts[token_id]._shares_deposited;
        uint256 tx_id = m_nft_catalog.approveTransaction(m_company_account, account, token_id, shares_available, 0, false);
        m_nft_catalog.implementTransaction(tx_id);

        uint256 governance_tokens_for_this_nft =
            m_deposits[account][project_id]._gov_tokens_by_nfts[token_id]._tokens_issued;

        _burn(account, project_id, governance_tokens_for_this_nft);

        m_deposits[account][project_id]._gov_tokens =
            m_deposits[account][project_id]._gov_tokens.sub(governance_tokens_for_this_nft);
        delete m_deposits[account][project_id]._gov_tokens_by_nfts[token_id];
        IterableSet.erase(m_deposits[msg.sender][project_id]._nfts, token_id);

        emit NFTsWithdrawn(account, project_id, token_id, governance_tokens_for_this_nft);
        return true;
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }

    /**
 * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint256 project_id, uint32 pos) public view virtual returns (Checkpoint memory) {
        return _checkpoints[account][project_id][pos];
    }

    /**
 * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account, uint256 project_id) public view virtual returns (uint32) {
        return SafeCast.toUint32(_checkpoints[account][project_id].length);
    }

    /**
  * @dev Get the address `account` is currently delegating to.
     */
    function delegates(address account, uint256 project_id) public view virtual returns (address) {
        return _delegates[account][project_id];
    }

    /**
     * @dev Gets the current votes balance for `account`
     */
    function getVotes(address account, uint256 project_id) public view virtual returns (uint256) {
        uint256 pos = _checkpoints[account][project_id].length;
        return pos == 0 ? 0 : _checkpoints[account][project_id][pos - 1].votes;
    }

    /**
 * @dev Retrieve the number of votes for `account` at the end of `blockNumber`.
     *
     * Requirements:
     *
     * - `blockNumber` must have been already mined
     */
    function getPastVotes(address account, uint256 blockNumber, uint256 project_id) public view virtual returns (uint256) {
        require(blockNumber < block.number, "GovernanceToken: block not yet mined");
        return _checkpointsLookup(_checkpoints[account][project_id], blockNumber);
    }

    /**
  * @dev Retrieve the `totalSupply` at the end of `blockNumber`. Note, this value is the sum of all balances.
     * It is but NOT the sum of all the delegated votes!
     *
     * Requirements:
     *
     * - `blockNumber` must have been already mined
     */
    function getPastTotalSupply(uint256 blockNumber) public view virtual returns (uint256) {
        require(blockNumber < block.number, "GovernanceToken: block not yet mined");
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    /**
 * @dev Lookup a value in a list of (sorted) checkpoints.
     */
    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 blockNumber) private view returns (uint256) {
        // We run a binary search to look for the earliest checkpoint taken after `blockNumber`.
        //
        // During the loop, the index of the wanted checkpoint remains in the range [low-1, high).
        // With each iteration, either `low` or `high` is moved towards the middle of the range to maintain the invariant.
        // - If the middle checkpoint is after `blockNumber`, we look in [low, mid)
        // - If the middle checkpoint is before or equal to `blockNumber`, we look in [mid+1, high)
        // Once we reach a single value (when low == high), we've found the right checkpoint at the index high-1, if not
        // out of bounds (in which case we're looking too far in the past and the result is 0).
        // Note that if the latest checkpoint available is exactly for `blockNumber`, we end up with an index that is
        // past the end of the array, so we technically don't find a checkpoint after `blockNumber`, but it works out
        // the same.
        uint256 high = ckpts.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (ckpts[mid].fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high == 0 ? 0 : ckpts[high - 1].votes;
    }


    /**
 * @dev Delegate votes from the sender to `delegatee`.
     */
    function delegate(address delegatee, uint256 project_id) public virtual {
        _delegate(_msgSender(), delegatee, project_id);
    }

    /**
 * @dev Change delegation for `delegator` to `delegatee`.
     *
     * Emits events {DelegateChanged} and {DelegateVotesChanged}.
     */
    function _delegate(address delegator, address delegatee, uint256 project_id) internal virtual {
        address currentDelegate = delegates(delegator, project_id);
        //        uint256 delegatorBalance = balanceOf(delegator);  removed
        uint256 delegatorBalance = m_deposits[delegator][project_id]._gov_tokens;
        _delegates[delegator][project_id] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee, project_id);

        _moveVotingPower(currentDelegate, delegatee, delegatorBalance, project_id);
    }

    function _moveVotingPower(
        address src,
        address dst,
        uint256 amount,
        uint256 project_id
    ) private {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[src][project_id], _subtract, amount);
                emit DelegateVotesChanged(src, oldWeight, newWeight, project_id);
            }

            if (dst != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[dst][project_id], _add, amount);
                emit DelegateVotesChanged(dst, oldWeight, newWeight, project_id);
            }
        }
    }

    function _writeCheckpoint(
        Checkpoint[] storage ckpts,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) private returns (uint256 oldWeight, uint256 newWeight) {
        uint256 pos = ckpts.length;
        oldWeight = pos == 0 ? 0 : ckpts[pos - 1].votes;
        newWeight = op(oldWeight, delta);

        if (pos > 0 && ckpts[pos - 1].fromBlock == block.number) {
            ckpts[pos - 1].votes = SafeCast.toUint224(newWeight);
        } else {
            ckpts.push(Checkpoint({fromBlock: SafeCast.toUint32(block.number), votes: SafeCast.toUint224(newWeight)}));
        }
    }

    /**
 * @dev Delegates votes from signer to `delegatee`
     */
    function delegateBySig(
        address delegatee,
        uint256 project_id,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(block.timestamp <= expiry, "ERC20Votes: signature expired");
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        require(nonce == _useNonce(signer), "ERC20Votes: invalid nonce");
        _delegate(signer, delegatee, project_id);
    }

    /**
     * @dev Maximum token supply. Defaults to `type(uint224).max` (2^224^ - 1).
     */
    function _maxSupply() internal view virtual returns (uint224) {
        return type(uint224).max;
    }

    /**
     * @dev Snapshots the totalSupply after it has been increased.
     */
    function _mint(address account, uint256 amount) internal virtual override {
        super._mint(account, amount);
        require(totalSupply() <= _maxSupply(), "ERC20Votes: total supply risks overflowing votes");

        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
    }
    function _mint(address account, uint256 project_id, uint256 amount) internal virtual {
        super._mint(account, amount);
        require(totalSupply() <= _maxSupply(), "ERC20Votes: total supply risks overflowing votes");

        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
        _writeCheckpoint(_checkpoints[account][project_id], _add, amount);
    }


    /**
     * @dev Snapshots the totalSupply after it has been decreased.
     */
    function _burn(address account, uint256 amount) internal virtual override {
        super._burn(account, amount);

        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
    }
    function _burn(address account, uint256 project_id, uint256 amount) internal virtual {
        super._burn(account, amount);

        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
        _writeCheckpoint(_checkpoints[account][project_id], _subtract, amount);
    }


    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }


    /**
    * @dev Move voting power when tokens are transferred.
     *
     * Emits a {DelegateVotesChanged} event.
     */

    /**
     * UNCLEAR IT IS NEEDED AT LL.
     */

    /**
        function _afterTokenTransfer(
            address from,
            address to,
            uint256 amount
        ) internal virtual override {
            super._afterTokenTransfer(from, to, amount);

            _moveVotingPower(delegates(from), delegates(to), amount);
        }
    */
}


