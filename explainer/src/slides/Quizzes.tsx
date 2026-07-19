import { Quiz } from "../components/Quiz";
import type { QuizQuestion } from "../components/Quiz";

const FOUNDATIONS: QuizQuestion[] = [
  {
    q: "A user supplied 100 USDC when the liquidityIndex was 1.00. The index is now 1.10. What does aUSDC.balanceOf show?",
    options: [
      "100 — balances only change on interactions",
      "110 — scaled balance × current index",
      "100 plus claimable rewards",
      "It depends on the borrow index",
    ],
    answer: 1,
    explain:
      "The token stores 100 scaled units; balanceOf multiplies by the live liquidityIndex (floor-rounded since v3.5).",
    slideId: "tokenization",
    slideTitle: "Tokenization",
  },
  {
    q: "Utilization rises above the optimal usage ratio. What happens to the borrow rate?",
    options: [
      "It keeps climbing at slope 1",
      "It is capped at the optimal rate",
      "Slope 2 kicks in — the curve steepens sharply",
      "Only the supply rate changes",
    ],
    answer: 2,
    explain:
      "Past the kink, the excess ratio (u − uopt)/(1 − uopt) is priced with slope 2 to defend exit liquidity.",
    slideId: "rate-model",
    slideTitle: "The interest rate model",
  },
  {
    q: "Which index compounds per second?",
    options: [
      "liquidityIndex",
      "variableBorrowIndex",
      "Both",
      "Neither — both are linear",
    ],
    answer: 1,
    explain:
      "Borrow interest compounds per second (binomial approximation in MathUtils); supply interest cumulates linearly between updates. The spread funds the reserve factor.",
    slideId: "indexes",
    slideTitle: "Indexes & interest accrual",
  },
  {
    q: "Since v3.1, where does the protocol read available liquidity from?",
    options: [
      "IERC20(asset).balanceOf(aToken)",
      "The virtualUnderlyingBalance counter",
      "The oracle",
      "The treasury",
    ],
    answer: 1,
    explain:
      "Virtual accounting tracks every in/outflow internally, so donations to the aToken cannot distort utilization or rates.",
    slideId: "bitmaps",
    slideTitle: "Bitmaps & storage layout",
  },
];

const CORE_FLOWS: QuizQuestion[] = [
  {
    q: "Since v3.5, when does borrow() check the health factor?",
    options: [
      "Before any state change",
      "After minting the debt token",
      "Only if the asset is volatile",
      "Never — only LTV is checked",
    ],
    answer: 1,
    explain:
      "validateHFAndLtv runs after the vToken mint — one computation on final state, no duplicated edge cases.",
    slideId: "borrow-flow",
    slideTitle: "Borrow & repay",
  },
  {
    q: "HF is 0.97; the borrower has $5,000 collateral and $5,000 debt on the targeted reserve. How much debt can one liquidationCall repay?",
    options: [
      "All of it",
      "50% of the total debt",
      "Only $1,000",
      "Nothing — HF must be below 0.95",
    ],
    answer: 1,
    explain:
      "With HF between 0.95 and 1 and both sides ≥ $2,000, the default position-wide close factor of 50% applies.",
    slideId: "liquidation-math",
    slideTitle: "Liquidations: the math",
  },
  {
    q: "A liquidation would leave the borrower with $400 debt and $600 collateral on that reserve. What happens?",
    options: [
      "It executes normally",
      "The protocol tops up the difference",
      "It reverts with MustNotLeaveDust()",
      "The leftover converts to deficit",
    ],
    answer: 2,
    explain:
      "Leftover debt and collateral must each be zero or ≥ $1,000 (MIN_LEFTOVER_BASE) — dust positions are forbidden since v3.3.",
    slideId: "liquidation-math",
    slideTitle: "Liquidations: the math",
  },
  {
    q: "After a liquidation the borrower holds zero collateral but $200 of debt. What does the protocol do?",
    options: [
      "Waits for the borrower to repay",
      "Burns the debt and books it as reserve deficit",
      "Socializes it across suppliers immediately",
      "Reverts the liquidation",
    ],
    answer: 1,
    explain:
      "The v3.3 bad-debt cleanup burns unrecoverable debt and records it in reserve.deficit, later coverable by Umbrella.",
    slideId: "bad-debt",
    slideTitle: "Bad debt & the deficit",
  },
];

const EMODES_V37: QuizQuestion[] = [
  {
    q: "In a NON-isolated eMode, what LTV does enabled collateral outside the category bitmap get?",
    options: [
      "Zero",
      "The eMode LTV",
      "Its regular base LTV",
      "The average of both",
    ],
    answer: 2,
    explain:
      "That base-LTV fallback is exactly the loophole the v3.7 isolated flag closes.",
    slideId: "emodes",
    slideTitle: "Efficiency modes",
  },
  {
    q: "In an ISOLATED eMode, collateral outside the bitmap…",
    options: [
      "is seized by the protocol",
      "contributes zero LTV but still counts for the health factor",
      "is automatically withdrawn",
      "blocks all borrowing forever",
    ],
    answer: 1,
    explain:
      "getUserReserveLtv returns 0 for it; the liquidation threshold — and therefore the HF — is unaffected.",
    slideId: "isolated-emode",
    slideTitle: "Isolated eMode",
  },
  {
    q: "Which of these was removed in v3.7?",
    options: [
      "Virtual accounting",
      "eModes",
      "The L2 sequencer PriceOracleSentinel",
      "Flash loans",
    ],
    answer: 2,
    explain:
      "Unreliable sequencer-uptime signals caused false positives that blocked liquidations when they were needed most.",
    slideId: "v37-changes",
    slideTitle: "v3.7 removals",
  },
  {
    q: "What is true about reserve ids since v3.7?",
    options: [
      "They can be reused after dropReserve",
      "They rotate on every upgrade",
      "The reserves list is append-only — dropReserve is gone",
      "They moved to 32 bits",
    ],
    answer: 2,
    explain:
      "Dropping a reserve could recycle an id that eMode bitmaps, user bitmaps and integrations hardcode — so the flow was deleted.",
    slideId: "v37-changes",
    slideTitle: "v3.7 removals",
  },
];

function QuizSlide({
  section,
  questions,
  blurb,
}: {
  section: string;
  questions: QuizQuestion[];
  blurb: string;
}) {
  return (
    <div>
      <span className="slide-kicker">{section} · knowledge check</span>
      <h2 className="slide-title">
        Test <span className="grad">yourself</span>
      </h2>
      <p className="slide-subtitle">{blurb}</p>
      <Quiz questions={questions} />
    </div>
  );
}

export function QuizFoundations() {
  return (
    <QuizSlide
      section="Foundations"
      questions={FOUNDATIONS}
      blurb="Four questions on the mechanics so far — scaled balances, the rate curve, indexes and virtual accounting. Each answer links back to the slide that covers it."
    />
  );
}

export function QuizCoreFlows() {
  return (
    <QuizSlide
      section="Core flows"
      questions={CORE_FLOWS}
      blurb="Borrowing, health factors and the liquidation rulebook — the numbers come straight from LiquidationLogic."
    />
  );
}

export function QuizEModes() {
  return (
    <QuizSlide
      section="eModes & v3.7"
      questions={EMODES_V37}
      blurb="eMode LTV resolution and what v3.7 changed."
    />
  );
}
