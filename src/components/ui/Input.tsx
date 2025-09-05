import { cn } from './utils'
export default function Input({ className, ...props }: any){
return <input className={cn('input', className)} {...props} />
}