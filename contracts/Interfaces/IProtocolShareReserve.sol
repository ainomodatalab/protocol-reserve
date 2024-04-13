pragma solidity ^0.8.25;

interface IProtocolShareReserve {
    enum IncomeType {
        SPREAD,
        LIQUIDATION
    }

    function updateAssetsState(
        address comptroller,
        address asset,
        IncomeType incomeType
    ) external;
}
