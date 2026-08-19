CREATE TABLE public.todos (
    id bigserial PRIMARY KEY,
    title text NOT NULL,
    completed boolean NOT NULL DEFAULT false
);
