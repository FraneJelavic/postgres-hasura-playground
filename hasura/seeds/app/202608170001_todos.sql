INSERT INTO public.todos (title)
SELECT 'Seeded playground todo'
WHERE NOT EXISTS (
    SELECT 1
    FROM public.todos
    WHERE title = 'Seeded playground todo'
);
