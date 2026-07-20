import { useState } from "react";

export type QuizQuestion = {
  q: string;
  options: string[];
  /** index of the correct option */
  answer: number;
  explain: string;
  /** slide id to review, rendered as a deep link */
  slideId: string;
  slideTitle: string;
};

export function Quiz({ questions }: { questions: QuizQuestion[] }) {
  const [picked, setPicked] = useState<(number | null)[]>(
    questions.map(() => null)
  );

  const answered = picked.filter((p) => p !== null).length;
  const correct = picked.filter((p, i) => p === questions[i].answer).length;

  const pick = (qi: number, oi: number) => {
    setPicked((prev) => {
      if (prev[qi] !== null) return prev;
      const next = [...prev];
      next[qi] = oi;
      return next;
    });
  };

  return (
    <div>
      <div className="quiz-score">
        <span
          className={`pill ${
            answered === questions.length
              ? correct === questions.length
                ? "good"
                : "warn"
              : "teal"
          }`}
        >
          {answered === questions.length
            ? `Score: ${correct} / ${questions.length}`
            : `${answered} / ${questions.length} answered`}
        </span>
        <button
          className="icon-btn"
          onClick={() => setPicked(questions.map(() => null))}
        >
          ↺ Reset
        </button>
      </div>
      {questions.map((q, qi) => {
        const sel = picked[qi];
        const done = sel !== null;
        return (
          <div className="quiz-q" key={qi}>
            <div className="q-text">
              <span className="q-num">Q{qi + 1}</span>
              {q.q}
            </div>
            <div className="quiz-options">
              {q.options.map((opt, oi) => {
                let cls = "quiz-option";
                if (done && oi === q.answer) cls += " correct";
                else if (done && oi === sel) cls += " wrong";
                return (
                  <button
                    key={oi}
                    className={cls}
                    disabled={done}
                    onClick={() => pick(qi, oi)}
                  >
                    {String.fromCharCode(65 + oi)}. {opt}
                  </button>
                );
              })}
            </div>
            {done && (
              <div className="quiz-explain">
                {sel === q.answer ? "Correct. " : "Not quite. "}
                {q.explain}{" "}
                <a href={`#/${q.slideId}`}>Review: {q.slideTitle} →</a>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
