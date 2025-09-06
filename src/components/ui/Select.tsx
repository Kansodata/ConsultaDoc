import React, { SelectHTMLAttributes } from "react";

type SelectProps = SelectHTMLAttributes<HTMLSelectElement>;

export default function Select({ children, ...props }: SelectProps) {
  return (
    <select className="input" {...props}>
      {children}
    </select>
  );
}
