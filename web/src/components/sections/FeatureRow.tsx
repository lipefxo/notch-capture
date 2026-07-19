import Image from "next/image";
import type { ReactNode } from "react";

type FeatureRowProps = {
  eyebrow: string;
  title: string;
  copy: ReactNode;
  image: string;
  imageAlt: string;
  imageWidth: number;
  imageHeight: number;
  reverse?: boolean;
  tone?: "white" | "gray";
  className?: string;
};

export function FeatureRow({ eyebrow, title, copy, image, imageAlt, imageWidth, imageHeight, reverse, tone = "white", className = "" }: FeatureRowProps) {
  return (
    <section className={`featureSection tone-${tone} ${className}`}>
      <div className={`featureRow ${reverse ? "reverse" : ""}`}>
        <div className="featureCopy">
          <p className="eyebrow">{eyebrow}</p>
          <h2>{title}</h2>
          <div className="featureBody">{copy}</div>
        </div>
        <div className="featureMedia">
          <Image src={image} alt={imageAlt} width={imageWidth} height={imageHeight} sizes="(max-width: 800px) 90vw, 52vw" />
        </div>
      </div>
    </section>
  );
}
