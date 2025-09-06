import { cn } from './utils'
export default function Button({ as:As='button', className, ...props }: any){
return <As className={cn('btn', className)} {...props} />
}