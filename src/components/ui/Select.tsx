export default function Select({ children, ...props }: any){
return <select className="input" {...props}>{children}</select>
}