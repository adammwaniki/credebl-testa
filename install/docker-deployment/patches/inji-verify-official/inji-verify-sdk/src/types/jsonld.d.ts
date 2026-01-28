/**
 * Type declarations for jsonld library
 */
declare module 'jsonld' {
  interface CanonizeOptions {
    algorithm?: 'URDNA2015' | 'URGNA2012';
    format?: 'application/n-quads' | 'application/nquads';
    documentLoader?: (url: string) => Promise<{
      contextUrl: string | null;
      document: object;
      documentUrl: string;
    }>;
    expansionMap?: (info: any) => any;
    skipExpansion?: boolean;
    inputFormat?: string;
    useNative?: boolean;
    safe?: boolean;
  }

  export function canonize(input: object, options?: CanonizeOptions): Promise<string>;

  export function expand(input: object, options?: any): Promise<object[]>;

  export function compact(input: object, ctx: object, options?: any): Promise<object>;

  export function flatten(input: object, ctx?: object, options?: any): Promise<object>;

  export function frame(input: object, frame: object, options?: any): Promise<object>;

  export function normalize(input: object, options?: CanonizeOptions): Promise<string>;

  export function fromRDF(dataset: string, options?: any): Promise<object[]>;

  export function toRDF(input: object, options?: any): Promise<string>;

  export function processContext(activeCtx: object, localCtx: object, options?: any): Promise<object>;
}
