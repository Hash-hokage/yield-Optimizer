import { useReadContract, useWriteContract, useAccount } from 'wagmi'
import { yieldOptimizerABI } from '@/abi/YieldOptimizer'
import { mockERC20ABI } from '@/abi/MockERC20'
import { Address } from 'viem'

const OPTIMIZER_ADDRESS = process.env.NEXT_PUBLIC_YIELD_OPTIMIZER_ADDRESS as Address
const USDC_ADDRESS = process.env.NEXT_PUBLIC_USDC_ADDRESS as Address

export function useYieldOptimizer() {
  const { address } = useAccount()

  // --- READS ---

  const { data: usdcBalance, refetch: refetchUsdcBalance } = useReadContract({
    address: USDC_ADDRESS,
    abi: mockERC20ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: USDC_ADDRESS,
    abi: mockERC20ABI,
    functionName: 'allowance',
    args: address ? [address, OPTIMIZER_ADDRESS] : undefined,
    query: { enabled: !!address },
  })

  const { data: userShares, refetch: refetchUserShares } = useReadContract({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    functionName: 'userShares',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: totalOptimizerShares, refetch: refetchTotalShares } = useReadContract({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    functionName: 'totalOptimizerShares',
  })

  // --- WRITES ---

  const { writeContractAsync: mintTestUSDC, isPending: isMinting } = useWriteContract()
  const { writeContractAsync: approveUSDC, isPending: isApproving } = useWriteContract()
  const { writeContractAsync: deposit, isPending: isDepositing } = useWriteContract()
  const { writeContractAsync: withdraw, isPending: isWithdrawing } = useWriteContract()

  // --- WRAPPER FUNCTIONS ---

  const handleMintTestUSDC = async (amount: bigint) => {
    if (!address) return
    await mintTestUSDC({
      address: USDC_ADDRESS,
      abi: mockERC20ABI,
      functionName: 'mint',
      args: [address, amount],
    })
    refetchUsdcBalance()
  }

  const handleApproveUSDC = async (amount: bigint) => {
    await approveUSDC({
      address: USDC_ADDRESS,
      abi: mockERC20ABI,
      functionName: 'approve',
      args: [OPTIMIZER_ADDRESS, amount],
    })
    refetchUsdcAllowance()
  }

  const handleDeposit = async (amount: bigint) => {
    await deposit({
      address: OPTIMIZER_ADDRESS,
      abi: yieldOptimizerABI,
      functionName: 'deposit',
      args: [amount],
    })
    refetchUsdcBalance()
    refetchUsdcAllowance()
    refetchUserShares()
    refetchTotalShares()
  }

  const handleWithdraw = async (shares: bigint) => {
    await withdraw({
      address: OPTIMIZER_ADDRESS,
      abi: yieldOptimizerABI,
      functionName: 'withdraw',
      args: [shares],
    })
    refetchUsdcBalance()
    refetchUserShares()
    refetchTotalShares()
  }

  const refetchAll = () => {
    refetchUsdcBalance()
    refetchUsdcAllowance()
    refetchUserShares()
    refetchTotalShares()
  }

  return {
    // State
    address,
    usdcBalance,
    usdcAllowance,
    userShares,
    totalOptimizerShares,
    
    // Loading States
    isMinting,
    isApproving,
    isDepositing,
    isWithdrawing,
    
    // Actions
    handleMintTestUSDC,
    handleApproveUSDC,
    handleDeposit,
    handleWithdraw,
    refetchAll,
  }
}
