import React, { ComponentProps, ElementType } from "react";
import { cn } from "./utils";

type ButtonProps = ComponentProps<"button"> & {
  as?: ElementType;
};

export default function Button({
  as: As = "button",
  className,
  ...props
}: ButtonProps) {
  return <As className={cn("btn", className)} {...props} />;
}
