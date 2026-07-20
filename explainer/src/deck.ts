import type {ComponentType} from 'react';
import {TitleSlide} from './slides/TitleSlide';
import {WhatIsAave} from './slides/WhatIsAave';
import {Architecture} from './slides/Architecture';
import {PoolLibraries} from './slides/PoolLibraries';
import {Bitmaps} from './slides/Bitmaps';
import {Tokenization} from './slides/Tokenization';
import {Indexes} from './slides/Indexes';
import {RateModel} from './slides/RateModel';
import {SupplyFlow} from './slides/SupplyFlow';
import {BorrowFlow} from './slides/BorrowFlow';
import {HealthFactor} from './slides/HealthFactor';
import {LiquidationFlow} from './slides/LiquidationFlow';
import {LiquidationMath} from './slides/LiquidationMath';
import {BadDebt} from './slides/BadDebt';
import {EModes} from './slides/EModes';
import {IsolatedEMode} from './slides/IsolatedEMode';
import {V37Changes} from './slides/V37Changes';
import {FlashLoans} from './slides/FlashLoans';
import {L2PoolSlide} from './slides/L2PoolSlide';
import {ListingPipeline} from './slides/ListingPipeline';
import {Periphery} from './slides/Periphery';
import {Security} from './slides/Security';
import {Timeline} from './slides/Timeline';
import {Resources} from './slides/Resources';
import {GlossarySlide} from './slides/GlossarySlide';
import {ErrorsCatalog} from './slides/ErrorsCatalog';
import {QuizFoundations, QuizCoreFlows, QuizEModes} from './slides/Quizzes';

export type SlideDef = {id: string; title: string; component: ComponentType};
export type SectionDef = {title: string; slides: SlideDef[]};

export const SECTIONS: SectionDef[] = [
  {
    title: 'Foundations',
    slides: [
      {id: 'intro', title: 'Aave v3.7 — Developer Explainer', component: TitleSlide},
      {id: 'what-is-aave', title: 'What is Aave?', component: WhatIsAave},
      {id: 'architecture', title: 'Contract architecture', component: Architecture},
      {id: 'pool-libraries', title: 'The Pool & its logic libraries', component: PoolLibraries},
      {id: 'bitmaps', title: 'Bitmaps & storage layout', component: Bitmaps},
      {id: 'tokenization', title: 'Tokenization: aTokens & debt tokens', component: Tokenization},
      {id: 'indexes', title: 'Indexes & interest accrual', component: Indexes},
      {id: 'rate-model', title: 'The interest rate model', component: RateModel},
      {id: 'quiz-foundations', title: 'Knowledge check: Foundations', component: QuizFoundations},
    ],
  },
  {
    title: 'Core flows',
    slides: [
      {id: 'supply-flow', title: 'Supply & withdraw', component: SupplyFlow},
      {id: 'borrow-flow', title: 'Borrow & repay', component: BorrowFlow},
      {id: 'health-factor', title: 'Health factor & borrowing power', component: HealthFactor},
      {id: 'liquidation-flow', title: 'Liquidations: the flow', component: LiquidationFlow},
      {id: 'liquidation-math', title: 'Liquidations: the math', component: LiquidationMath},
      {id: 'bad-debt', title: 'Bad debt & the deficit', component: BadDebt},
      {id: 'quiz-core-flows', title: 'Knowledge check: Core flows', component: QuizCoreFlows},
    ],
  },
  {
    title: 'eModes & v3.7',
    slides: [
      {id: 'emodes', title: 'Efficiency modes (eModes)', component: EModes},
      {id: 'isolated-emode', title: 'Isolated eMode — new in v3.7', component: IsolatedEMode},
      {id: 'v37-changes', title: 'v3.7 removals & simplification', component: V37Changes},
      {id: 'quiz-emodes', title: 'Knowledge check: eModes & v3.7', component: QuizEModes},
    ],
  },
  {
    title: 'Ecosystem',
    slides: [
      {id: 'flash-loans', title: 'Flash loans & UX features', component: FlashLoans},
      {id: 'l2pool', title: 'L2Pool & calldata compression', component: L2PoolSlide},
      {id: 'listing-pipeline', title: 'How an asset gets listed', component: ListingPipeline},
      {id: 'periphery', title: 'Periphery & special reserves', component: Periphery},
      {id: 'security', title: 'Governance, risk & security', component: Security},
      {id: 'timeline', title: 'Version history: v3.0 → v3.7', component: Timeline},
      {id: 'resources', title: 'Reading the code & resources', component: Resources},
    ],
  },
  {
    title: 'Reference',
    slides: [
      {id: 'glossary', title: 'Glossary', component: GlossarySlide},
      {id: 'errors', title: 'Error catalog', component: ErrorsCatalog},
    ],
  },
];

export const FLAT: (SlideDef & {section: string})[] = SECTIONS.flatMap((s) =>
  s.slides.map((sl) => ({...sl, section: s.title}))
);

export function slideIndexFromHash(): number {
  const id = window.location.hash.replace(/^#\/?/, '');
  const i = FLAT.findIndex((s) => s.id === id);
  return i >= 0 ? i : 0;
}
