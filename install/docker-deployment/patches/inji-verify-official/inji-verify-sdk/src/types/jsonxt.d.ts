/**
 * Type declarations for jsonxt library
 */
declare module 'jsonxt' {
  export interface Column {
    path: string;
    encoder: string;
  }

  export interface Template {
    columns: Column[];
    template: object;
  }

  export type TemplateResolver = (name: string) => Promise<Record<string, Template>>;

  /**
   * Pack a JSON document into a JSON-XT URI
   */
  export function pack(
    document: object,
    templates: Record<string, Template>,
    type: string,
    version: string,
    resolver?: string
  ): Promise<string>;

  /**
   * Unpack a JSON-XT URI back into a JSON document
   */
  export function unpack(
    uri: string,
    resolver: TemplateResolver
  ): Promise<object>;
}
