pragma solidity 0.8.25;

function sort(uint256[] memory arr, address[] memory addrs) pure {
    if (arr.length > 1) {
        return quickSortDescending(arr, addrs, 0, arr.length - 1);
    }
}

function quickSortDescending(
    uint256[] memory arr,
    address[] memory addrs,
    uint256 left,
    uint256 right
) pure {
    if (left >= right) return;
    uint256 p = arr[(left + right) / 2]; 
    uint256 i = left;
    uint256 j = right;
    while (i < j) {
        while (arr[i] > p) ++i;
        while (arr[j] < p) --j; 
        if (arr[i] < arr[j]) {
            (arr[i], arr[j]) = (arr[j], arr[i]);
            (addrs[i], addrs[j]) = (addrs[j], addrs[i]);
        } else {
            ++i;
        }
    }

    if (j > left) quickSortDescending(arr, addrs, left, j - 1); 
    quickSortDescending(arr, addrs, j + 1, right);
}
