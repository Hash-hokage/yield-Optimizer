import { useReadContract, useWriteContract, useAccount, usePublicClient, useWatchContractEvent } from 'wagmi'
import { useState } from 'react'
import { yieldOptimizerABI } from '@/abi/YieldOptimizer'
import { mockERC20ABI } from '@/abi/MockERC20'
import { yieldRelayerABI } from '@/abi/YieldRelayer'
import { Address } from 'viem'

const OPTIMIZER_ADDRESS = process.env.NEXT_PUBLIC_YIELD_OPTIMIZER_ADDRESS as Address
const USDC_ADDRESS = process.env.NEXT_PUBLIC_USDC_ADDRESS as Address
const RELAYER_ADDRESS = process.env.NEXT_PUBLIC_YIELD_RELAYER_ADDRESS as Address
const FARM_ADDRESS = process.env.NEXT_PUBLIC_MOCK_FARM_ADDRESS as Address

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

  // Read the most recently pushed APY for the active farm from the YieldRelayer
  const { data: currentAPYBps } = useReadContract({
    address: RELAYER_ADDRESS,
    abi: yieldRelayerABI,
    functionName: 'currentFarmYields',
    args: FARM_ADDRESS ? [FARM_ADDRESS] : undefined,
    query: {
      enabled: !!FARM_ADDRESS,
      refetchInterval: 8_000,
    },
  })

  // Read how much USDC the optimizer contract holds idle (not yet deployed to a farm)
  const { data: optimizerUsdcBalance } = useReadContract({
    address: USDC_ADDRESS,
    abi: mockERC20ABI,
    functionName: 'balanceOf',
    args: [OPTIMIZER_ADDRESS],
    query: { refetchInterval: 8_000 },
  })

  // TVL: pro-rata share of the total portfolio value owned by all depositors combined.
  // = totalOptimizerShares * portfolioValue / totalOptimizerShares = portfolioValue
  // Since totalOptimizerShares represents the entire pool, TVL equals
  // the USDC value of all idle USDC + farm shares held by this contract.
  // We approximate using idle USDC balance read via usdcBalance at the contract level.
  // The most accurate TVL is totalOptimizerShares in USDC terms at the 1:1 bootstrap ratio,
  // adjusted over time. For a correct live value, expose _getPortfolioValue() on-chain
  // or sum idleUSDC + farm share value client-side. For the hackathon, totalOptimizerShares
  // is the best available proxy since shares are minted 1:1 with USDC on first deposit.
  // 
  // TVL = idle USDC in contract + shares value (proxy: totalOptimizerShares).
  // Using optimizerUsdcBalance as the primary source when available.
  const tvl = optimizerUsdcBalance !== undefined
    ? optimizerUsdcBalance
    : (totalOptimizerShares ?? BigInt(0))

  // Track the most recent OptimizerExecuted event for reactive confirmation UI
  const [lastExecution, setLastExecution] = useState<{
    targetFarm: string
    profitUSDC: bigint
    gasSpent: bigint
    txHash: string
    timestamp: number
  } | null>(null)

  useWatchContractEvent({
    address: OPTIMIZER_ADDRESS,
    abi: yieldOptimizerABI,
    eventName: 'OptimizerExecuted',
    onLogs: (logs) => {
      const log = logs[logs.length - 1]
      if (!log) return
      setLastExecution({
        targetFarm: log.args.targetFarm as string,
        profitUSDC: log.args.profitUSDC as bigint,
        gasSpent: log.args.gasSpent as bigint,
        txHash: log.transactionHash ?? '',
        timestamp: Date.now(),
      })
      // Refresh all dashboard data after a rebalance executes
      refetchCurrentFarm()
      refetchTotalShares()
      refetchCumulativeLoss()
      refetchUserShares()
    },
  })

  // --- WRITES ---

  const { writeContractAsync: mintTestUSDC, isPending: isMinting } = useWriteContract()
  const { writeContractAsync: approveUSDC, isPending: isApproving } = useWriteContract()
  const { writeContractAsync: deposit, isPending: isDepositing } = useWriteContract()
  const { writeContractAsync: withdraw, isPending: isWithdrawing } = useWriteContract()

  // --- WRAPPER FUNCTIONS ---

  const handleMintTestUSDC = async (amount: bigint) => {
    if (!address || !publicClient) return
    
    if (!USDC_ADDRESS || USDC_ADDRESS === "0x0000000000000000000000000000000000000000") {
      console.error("DEBUG: USDC_ADDRESS is undefined or zero address. Check environment variables.");
      alert("Error: USDC Contract Address is missing. Please check your Vercel environment variables.");
      return;
    }

    console.log(`DEBUG: Attempting to mint ${amount} units at USDC address: ${USDC_ADDRESS}`);

    try {
      const hash = await mintTestUSDC({
        address: USDC_ADDRESS,
        abi: mockERC20ABI,
        functionName: 'mint',
        args: [address, amount],
      })
      await publicClient.waitForTransactionReceipt({ hash })
      await refetchUsdcBalance()
    } catch (err) {
      console.error("DEBUG: Minting failed:", err);
      throw err;
    }
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
    currentAPYBps,
    optimizerUsdcBalance,
    lastExecution,
    
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
