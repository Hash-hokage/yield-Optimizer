import { useReadContract, useWriteContract, useAccount, usePublicClient } from 'wagmi'
import { yieldOptimizerABI } from '@/abi/YieldOptimizer'
import { mockERC20ABI } from '@/abi/MockERC20'
import { Address } from 'viem'

const OPTIMIZER_ADDRESS = process.env.NEXT_PUBLIC_YIELD_OPTIMIZER_ADDRESS as Address
const USDC_ADDRESS = process.env.NEXT_PUBLIC_USDC_ADDRESS as Address

export function useYieldOptimizer() {
  const { address } = useAccount()
  const publicClient = usePublicClient()

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

  const { data: cumulativeLoss, refetch: refetchCumulativeLoss } = useReadContract({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    functionName: 'cumulativeLoss',
    query: { refetchInterval: 10_000 }, // poll every 10 seconds
  })

  const { data: maxLossThreshold, refetch: refetchMaxLossThreshold } = useReadContract({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    functionName: 'maxLossThreshold',
  })

  const { data: isPaused } = useReadContract({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    functionName: 'isPaused',
    query: { refetchInterval: 10_000 },
  })

  const { data: currentFarm, refetch: refetchCurrentFarm } = useReadContract({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    functionName: 'currentFarm',
    query: { refetchInterval: 8_000 },
  })

  // TVL = totalOptimizerShares × (portfolioValue / totalShares)
  // Simplified: if all shares represent USDC at 1:1 on first deposit,
  // TVL ≈ totalOptimizerShares as a USDC amount (6 decimals)
  const tvl = totalOptimizerShares ?? BigInt(0)

  // --- WRITES ---

  const { writeContractAsync: mintTestUSDC, isPending: isMinting } = useWriteContract()
  const { writeContractAsync: approveUSDC, isPending: isApproving } = useWriteContract()
  const { writeContractAsync: deposit, isPending: isDepositing } = useWriteContract()
  const { writeContractAsync: withdraw, isPending: isWithdrawing } = useWriteContract()

  // --- WRAPPER FUNCTIONS ---

  const handleMintTestUSDC = async (amount: bigint) => {
    if (!address || !publicClient) return
    const hash = await mintTestUSDC({
      address: USDC_ADDRESS,
      abi: mockERC20ABI,
      functionName: 'mint',
      args: [address, amount],
    })
    await publicClient.waitForTransactionReceipt({ hash })
    await refetchUsdcBalance()
  }

  const handleApproveUSDC = async (amount: bigint) => {
    if (!publicClient) return
    const hash = await approveUSDC({
      address: USDC_ADDRESS,
      abi: mockERC20ABI,
      functionName: 'approve',
      args: [OPTIMIZER_ADDRESS, amount],
    })
    await publicClient.waitForTransactionReceipt({ hash })
    await refetchUsdcAllowance()
  }

  const handleDeposit = async (amount: bigint) => {
    if (!publicClient) return
    const hash = await deposit({
      address: OPTIMIZER_ADDRESS,
      abi: yieldOptimizerABI,
      functionName: 'deposit',
      args: [amount],
    })
    await publicClient.waitForTransactionReceipt({ hash })
    await refetchUsdcBalance()
    await refetchUsdcAllowance()
    await refetchUserShares()
    await refetchTotalShares()
  }

  const handleWithdraw = async (shares: bigint) => {
    if (!publicClient) return
    const hash = await withdraw({
      address: OPTIMIZER_ADDRESS,
      abi: yieldOptimizerABI,
      functionName: 'withdraw',
      args: [shares],
    })
    await publicClient.waitForTransactionReceipt({ hash })
    await refetchUsdcBalance()
    await refetchUserShares()
    await refetchTotalShares()
  }

  const refetchAll = () => {
    refetchUsdcBalance()
    refetchUsdcAllowance()
    refetchUserShares()
    refetchTotalShares()
    refetchCumulativeLoss()
    refetchMaxLossThreshold()
    refetchCurrentFarm()
  }

  return {
    // State
    address,
    usdcBalance,
    usdcAllowance,
    userShares,
    totalOptimizerShares,
    cumulativeLoss,
    maxLossThreshold,
    isPaused,
    tvl,
    currentFarm,
    
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
